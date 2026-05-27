"""
gemini_client.py — calls Gemini 2.5 Flash via Google AI Studio REST API.

The API key is fetched from AWS Secrets Manager at cold-start and cached
for the lifetime of the Lambda execution environment.
"""

import json
import logging
import os
import boto3
import requests

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

GEMINI_MODEL_ID = os.environ.get("GEMINI_MODEL_ID", "gemini-2.5-flash")
GEMINI_SECRET_ARN = os.environ.get("GEMINI_SECRET_ARN", "")

_cached_api_key: str | None = None


def _get_api_key() -> str:
    """Fetch Gemini API key from Secrets Manager; cache after first call."""
    global _cached_api_key
    if _cached_api_key:
        return _cached_api_key

    if not GEMINI_SECRET_ARN:
        raise EnvironmentError("GEMINI_SECRET_ARN environment variable is not set")

    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=GEMINI_SECRET_ARN)
    _cached_api_key = response["SecretString"].strip()
    logger.info("Gemini API key loaded from Secrets Manager")
    return _cached_api_key


def invoke_gemini(user_message: str, system_instruction: str, max_tokens: int = 1024) -> dict:
    """
    Call Gemini 2.5 Flash and return the parsed JSON response body.

    Parameters
    ----------
    user_message : str
        The user-turn content (logs + alarm context).
    system_instruction : str
        The system prompt telling Gemini it is an AWS SRE.
    max_tokens : int
        Maximum output tokens (default 1024; increase for verbose diagnoses).

    Returns
    -------
    dict
        Parsed JSON from Gemini's response text.  The caller is responsible
        for validating required keys (diagnosis, recommended_runbook, etc.).

    Raises
    ------
    ValueError
        If the HTTP request fails or the response cannot be parsed as JSON.
    """
    api_key = _get_api_key()
    url = (
        f"https://generativelanguage.googleapis.com/v1beta/models/"
        f"{GEMINI_MODEL_ID}:generateContent?key={api_key}"
    )

    payload = {
        "system_instruction": {
            "parts": [{"text": system_instruction}]
        },
        "contents": [
            {
                "role": "user",
                "parts": [{"text": user_message}]
            }
        ],
        "generationConfig": {
            "maxOutputTokens": max_tokens,
            "temperature": 0.2,          # low temperature = deterministic runbook selection
            "responseMimeType": "application/json"
        }
    }

    logger.info("Sending request to Gemini model: %s", GEMINI_MODEL_ID)
    response = requests.post(url, json=payload, timeout=30)

    if response.status_code != 200:
        raise ValueError(
            f"Gemini API returned HTTP {response.status_code}: {response.text[:500]}"
        )

    body = response.json()
    try:
        raw_text = body["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError) as exc:
        raise ValueError(f"Unexpected Gemini response structure: {body}") from exc

    logger.info("Gemini raw response text: %s", raw_text[:500])

    try:
        result = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        raise ValueError(
            f"Gemini response is not valid JSON: {raw_text[:500]}"
        ) from exc

    _validate_response(result)
    return result


_REQUIRED_KEYS = {"diagnosis", "recommended_runbook", "confidence", "reasoning"}
_ALLOWED_RUNBOOKS = {
    "restart_ecs_task",
    "restart_ec2_instance",
    "scale_out_asg",
    "rotate_rds_password",
    "increase_ecs_memory",
}
_ALLOWED_CONFIDENCE = {"high", "medium", "low"}


def _validate_response(result: dict) -> None:
    """Validate that Gemini returned all required fields with allowed values."""
    missing = _REQUIRED_KEYS - result.keys()
    if missing:
        raise ValueError(f"Gemini response missing required keys: {missing}")

    runbook = result.get("recommended_runbook", "")
    if runbook not in _ALLOWED_RUNBOOKS:
        raise ValueError(
            f"Gemini selected runbook '{runbook}' which is not in the allowed list: "
            f"{_ALLOWED_RUNBOOKS}"
        )

    confidence = result.get("confidence", "").lower()
    if confidence not in _ALLOWED_CONFIDENCE:
        raise ValueError(
            f"Gemini confidence '{confidence}' is not one of {_ALLOWED_CONFIDENCE}"
        )
    result["confidence"] = confidence  # normalise to lowercase
