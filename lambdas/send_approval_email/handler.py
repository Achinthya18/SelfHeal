"""
SendApprovalEmailLambda — handler.py

State 2 of the Step Functions workflow.

Input: the output dict from DiagnosticLambda, with one extra field added
       by Step Functions: taskToken (injected by the WaitForTaskToken state).

{
    "incident_id": "...",
    "created_at": "...",
    "alarm_name": "...",
    "resource_arn": "...",
    "diagnosis": "...",
    "recommended_runbook": "...",
    "confidence": "high|medium|low",
    "reasoning": "...",
    "logs_snapshot": "...",
    "taskToken": "<Step Functions task token>"
}

Output:
{
    "incident_id": "...",
    "created_at": "...",
    "email_sent": true
}
"""

import hashlib
import hmac
import json
import logging
import os
import time
from pathlib import Path

import boto3

from dynamo_client import save_incident

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

SES_SENDER_EMAIL = os.environ["SES_SENDER_EMAIL"]
SES_RECIPIENT_EMAIL = os.environ["SES_RECIPIENT_EMAIL"]
API_GATEWAY_BASE_URL = os.environ.get("API_GATEWAY_BASE_URL", "")
APPROVAL_TOKEN_SECRET = os.environ["APPROVAL_TOKEN_SECRET"]
APPROVAL_TOKEN_EXPIRY_MINUTES = int(os.environ.get("APPROVAL_TOKEN_EXPIRY_MINUTES", "15"))
DYNAMO_TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME", "self-healing-incidents")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

_ses_client = None
_TEMPLATE_PATH = Path(__file__).parent / "email_template.html"


def _get_ses():
    global _ses_client
    if _ses_client is None:
        _ses_client = boto3.client("ses")
    return _ses_client


def _generate_approval_token(incident_id: str, expiry_ts: int) -> str:
    """
    Generate an HMAC-SHA256 approval token.

    Format: "<expiry_unix_ts>.<hmac_hex>"
    The receiver recomputes the HMAC over "incident_id:expiry_ts" with the
    shared secret and checks that expiry_ts is still in the future.
    """
    message = f"{incident_id}:{expiry_ts}".encode()
    mac = hmac.new(APPROVAL_TOKEN_SECRET.encode(), message, hashlib.sha256)
    return f"{expiry_ts}.{mac.hexdigest()}"


def _build_approval_urls(incident_id: str, created_at: str, task_token: str, token: str) -> tuple[str, str]:
    """Return (approve_url, reject_url) for embedding in the email."""
    base = API_GATEWAY_BASE_URL.rstrip("/")
    params = (
        f"incident_id={incident_id}"
        f"&created_at={created_at}"
        f"&token={token}"
        f"&task_token={task_token}"
    )
    return f"{base}/approve?{params}", f"{base}/reject?{params}"


def _render_email(template: str, substitutions: dict) -> str:
    for key, value in substitutions.items():
        template = template.replace(f"{{{{{key}}}}}", str(value))
    return template


def _confidence_color(confidence: str) -> str:
    return {"high": "#27ae60", "medium": "#f39c12", "low": "#e74c3c"}.get(
        confidence.lower(), "#7f8c8d"
    )


def handler(event: dict, context) -> dict:
    logger.info("SendApprovalEmailLambda invoked, incident_id=%s", event.get("incident_id"))

    incident_id = event["incident_id"]
    created_at = event["created_at"]
    task_token = event["taskToken"]
    alarm_name = event.get("alarm_name", "unknown")
    resource_arn = event.get("resource_arn", "unknown")
    diagnosis = event["diagnosis"]
    recommended_runbook = event["recommended_runbook"]
    confidence = event["confidence"]
    reasoning = event.get("reasoning", "")
    logs_snapshot = event.get("logs_snapshot", "")

    # ── Generate approval token (15-min expiry) ─────────────────────────────
    expiry_ts = int(time.time()) + (APPROVAL_TOKEN_EXPIRY_MINUTES * 60)
    approval_token = _generate_approval_token(incident_id, expiry_ts)
    approve_url, reject_url = _build_approval_urls(
        incident_id, created_at, task_token, approval_token
    )

    # ── Save incident to DynamoDB ───────────────────────────────────────────
    ttl_90_days = int(time.time()) + (90 * 24 * 60 * 60)
    save_incident({
        "incident_id": incident_id,
        "created_at": created_at,
        "alarm_name": alarm_name,
        "resource_arn": resource_arn,
        "diagnosis": diagnosis,
        "recommended_runbook": recommended_runbook,
        "confidence": confidence,
        "reasoning": reasoning,
        "logs_snapshot": logs_snapshot,
        "status": "pending",
        "task_token": task_token,
        "approval_token": approval_token,
        "ttl": ttl_90_days,
    })

    # ── Render email HTML ───────────────────────────────────────────────────
    template = _TEMPLATE_PATH.read_text(encoding="utf-8")
    html_body = _render_email(template, {
        "alarm_name": alarm_name,
        "resource_arn": resource_arn,
        "diagnosis": diagnosis,
        "recommended_runbook": recommended_runbook,
        "confidence": confidence.upper(),
        "confidence_color": _confidence_color(confidence),
        "reasoning": reasoning,
        "approve_url": approve_url,
        "reject_url": reject_url,
        "expiry_minutes": APPROVAL_TOKEN_EXPIRY_MINUTES,
        "environment": ENVIRONMENT.upper(),
    })

    # ── Send SES email ──────────────────────────────────────────────────────
    subject = f"[{ENVIRONMENT.upper()}] Self-Healing: Action required — {alarm_name}"
    ses = _get_ses()
    ses.send_email(
        Source=SES_SENDER_EMAIL,
        Destination={"ToAddresses": [SES_RECIPIENT_EMAIL]},
        Message={
            "Subject": {"Data": subject, "Charset": "UTF-8"},
            "Body": {
                "Html": {"Data": html_body, "Charset": "UTF-8"},
                "Text": {
                    "Data": (
                        f"Alarm: {alarm_name}\n"
                        f"Resource: {resource_arn}\n"
                        f"Diagnosis: {diagnosis}\n"
                        f"Runbook: {recommended_runbook} (confidence: {confidence})\n\n"
                        f"APPROVE: {approve_url}\n"
                        f"REJECT:  {reject_url}\n\n"
                        f"This link expires in {APPROVAL_TOKEN_EXPIRY_MINUTES} minutes."
                    ),
                    "Charset": "UTF-8",
                },
            },
        },
    )

    logger.info(
        "Approval email sent to %s for incident %s", SES_RECIPIENT_EMAIL, incident_id
    )
    return {
        "incident_id": incident_id,
        "created_at": created_at,
        "email_sent": True,
    }
