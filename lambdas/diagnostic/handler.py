"""
DiagnosticLambda — handler.py

State 1 of the Step Functions workflow.

Input (from EventBridge via Step Functions):
{
    "alarm_name": "ecs-service-health-check-failed",
    "alarm_arn": "arn:aws:cloudwatch:...",
    "resource_arn": "arn:aws:ecs:ap-south-1:...:service/my-cluster/my-service",
    "log_group_name": "/ecs/my-service",
    "region": "ap-south-1"
}

Output:
{
    "incident_id": "<uuid>",
    "alarm_name": "...",
    "resource_arn": "...",
    "log_group_name": "...",
    "logs_snapshot": "<numbered log lines>",
    "diagnosis": "<plain-English diagnosis from Gemini>",
    "recommended_runbook": "<one of the 5 allowed runbook IDs>",
    "confidence": "high|medium|low",
    "reasoning": "<Gemini's reasoning paragraph>"
}
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

from cloudwatch_client import format_logs_for_prompt, get_recent_logs
from gemini_client import invoke_gemini

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# ── Gemini system prompt ────────────────────────────────────────────────────
_SYSTEM_PROMPT = """You are an expert AWS Site Reliability Engineer (SRE).
You are given a CloudWatch alarm that has just fired and the most recent log
events from the affected resource.

Your task is to:
1. Diagnose the root cause in plain English (2–4 sentences, no jargon).
2. Select the single most appropriate remediation runbook from the ALLOWED LIST below.
3. State your confidence level: "high", "medium", or "low".
4. Explain your reasoning in 1–3 sentences.

ALLOWED RUNBOOK LIST (you must select exactly one, no other values are valid):
- restart_ecs_task
- restart_ec2_instance
- scale_out_asg
- rotate_rds_password
- increase_ecs_memory

CRITICAL: You must respond with ONLY valid JSON — no markdown, no code fences,
no preamble. The JSON must have exactly these four keys:
{
  "diagnosis": "<string>",
  "recommended_runbook": "<one value from the allowed list>",
  "confidence": "<high|medium|low>",
  "reasoning": "<string>"
}"""


def _build_user_message(alarm_name: str, resource_arn: str, logs_text: str) -> str:
    return (
        f"CLOUDWATCH ALARM: {alarm_name}\n"
        f"AFFECTED RESOURCE: {resource_arn}\n\n"
        f"RECENT LOG EVENTS:\n{logs_text}\n\n"
        "Please diagnose this incident and select the appropriate runbook."
    )


def handler(event: dict, context) -> dict:
    """
    Lambda entry point.

    Parameters
    ----------
    event : dict
        Step Functions input payload (see module docstring).
    context : LambdaContext
        Standard Lambda context (used only for logging).

    Returns
    -------
    dict
        Enriched incident dict passed to the next Step Functions state.
    """
    logger.info("DiagnosticLambda invoked with event: %s", json.dumps(event))

    # ── Extract and validate input fields ──────────────────────────────────
    alarm_name = event.get("alarm_name", "unknown-alarm")
    alarm_arn = event.get("alarm_arn", "")
    resource_arn = event.get("resource_arn", "")
    log_group_name = event.get("log_group_name", "")

    if not log_group_name:
        logger.warning("No log_group_name in event — will use empty log snapshot")

    # ── Fetch logs ──────────────────────────────────────────────────────────
    log_events: list[str] = []
    if log_group_name:
        try:
            log_events = get_recent_logs(log_group_name, minutes=30, limit=100)
        except Exception as exc:
            logger.error("Failed to fetch logs: %s", exc)
            # Non-fatal: diagnose with whatever we have (empty logs)

    logs_text = format_logs_for_prompt(log_events)

    # ── Call Gemini ─────────────────────────────────────────────────────────
    user_message = _build_user_message(alarm_name, resource_arn, logs_text)
    diagnosis_result = invoke_gemini(
        user_message=user_message,
        system_instruction=_SYSTEM_PROMPT,
        max_tokens=512,
    )

    # ── Build the output payload ────────────────────────────────────────────
    incident_id = str(uuid.uuid4())
    timestamp = datetime.now(timezone.utc).isoformat()

    output = {
        "incident_id": incident_id,
        "created_at": timestamp,
        "alarm_name": alarm_name,
        "alarm_arn": alarm_arn,
        "resource_arn": resource_arn,
        "log_group_name": log_group_name,
        "logs_snapshot": logs_text,
        "diagnosis": diagnosis_result["diagnosis"],
        "recommended_runbook": diagnosis_result["recommended_runbook"],
        "confidence": diagnosis_result["confidence"],
        "reasoning": diagnosis_result["reasoning"],
    }

    logger.info(
        "Diagnosis complete: runbook=%s confidence=%s incident_id=%s",
        output["recommended_runbook"],
        output["confidence"],
        incident_id,
    )
    return output
