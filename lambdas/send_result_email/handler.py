"""
SendResultEmailLambda — handler.py

State 5 of the Step Functions workflow.

Input (from ExecuteRunbookLambda or a Catch block):
{
    "incident_id": "...",
    "created_at": "...",
    "alarm_name": "...",
    "resource_arn": "...",
    "recommended_runbook": "...",
    "diagnosis": "...",
    "ssm_execution_id": "...",   # present on success
    "ssm_status": "Success|Failed|Cancelled",
    "action": "approved|rejected",
    "error": "...",              # present on Lambda failure
    "cause": "..."               # present on Lambda failure
}

Output:
{
    "incident_id": "...",
    "result_email_sent": true
}
"""

import json
import logging
import os
from datetime import datetime, timezone
from pathlib import Path

import boto3

from dynamo_client import get_incident, update_incident_status

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

SES_SENDER_EMAIL = os.environ["SES_SENDER_EMAIL"]
SES_RECIPIENT_EMAIL = os.environ["SES_RECIPIENT_EMAIL"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "dev")

_ses_client = None
_ssm_client = None
_TEMPLATE_PATH = Path(__file__).parent / "email_template.html"


def _get_ses():
    global _ses_client
    if _ses_client is None:
        _ses_client = boto3.client("ses")
    return _ses_client


def _get_ssm():
    global _ssm_client
    if _ssm_client is None:
        _ssm_client = boto3.client("ssm")
    return _ssm_client


def _get_ssm_result(execution_id: str) -> dict:
    """Fetch SSM Automation execution details."""
    if not execution_id:
        return {}
    try:
        resp = _get_ssm().get_automation_execution(AutomationExecutionId=execution_id)
        exec_detail = resp.get("AutomationExecution", {})
        return {
            "status": exec_detail.get("AutomationExecutionStatus", "Unknown"),
            "start_time": str(exec_detail.get("ExecutionStartTime", "")),
            "end_time": str(exec_detail.get("ExecutionEndTime", "")),
            "failure_message": exec_detail.get("FailureMessage", ""),
        }
    except Exception as exc:
        logger.warning("Could not fetch SSM execution %s: %s", execution_id, exc)
        return {}


def _render_email(template: str, substitutions: dict) -> str:
    for key, value in substitutions.items():
        template = template.replace(f"{{{{{key}}}}}", str(value))
    return template


def _determine_final_status(event: dict) -> str:
    """Map the incoming event to a DynamoDB status string."""
    action = event.get("action", "")
    ssm_status = event.get("ssm_status", "")
    error = event.get("error") or event.get("error_info", {}).get("Error", "")

    if action == "rejected" or error == "HumanRejected":
        return "rejected"
    if error:
        return "failed"
    if ssm_status == "Success":
        return "resolved"
    return "failed"


def handler(event: dict, context) -> dict:
    logger.info("SendResultEmailLambda invoked: %s", json.dumps(event))

    incident_id = event.get("incident_id", "unknown")
    created_at = event.get("created_at", "")
    alarm_name = event.get("alarm_name", "unknown")
    resource_arn = event.get("resource_arn", "")
    recommended_runbook = event.get("recommended_runbook", "")
    diagnosis = event.get("diagnosis", "")
    ssm_execution_id = event.get("ssm_execution_id", "")
    action = event.get("action") or event.get("approval_callback", {}).get("action", "approved")
    # Step Functions Catch blocks inject error details under "error_info"; also accept top-level keys
    _error_info = event.get("error_info", {})
    error = event.get("error") or _error_info.get("Error", "")
    cause = event.get("cause") or _error_info.get("Cause", "")
    now = datetime.now(timezone.utc).isoformat()

    final_status = _determine_final_status(event)

    # ── Fetch SSM result (if available) ────────────────────────────────────
    ssm_result = _get_ssm_result(ssm_execution_id)
    ssm_status_text = ssm_result.get("status", "N/A")
    ssm_start = ssm_result.get("start_time", "N/A")
    ssm_end = ssm_result.get("end_time", "N/A")

    # ── Update DynamoDB ─────────────────────────────────────────────────────
    if created_at:
        update_incident_status(
            incident_id, created_at,
            status=final_status,
            extra={
                "resolved_at": now,
                "ssm_execution_id": ssm_execution_id,
            } if final_status in ("resolved", "failed") else {"resolved_at": now},
        )

    # ── Build email ─────────────────────────────────────────────────────────
    if final_status == "resolved":
        outcome_icon = "✅"
        outcome_title = "Fix Applied Successfully"
        outcome_color = "#27ae60"
        outcome_detail = (
            f"Runbook <strong>{recommended_runbook}</strong> executed successfully via SSM Automation.<br>"
            f"SSM Execution ID: <code>{ssm_execution_id}</code><br>"
            f"Started: {ssm_start}<br>"
            f"Completed: {ssm_end}"
        )
    elif final_status == "rejected":
        outcome_icon = "❌"
        outcome_title = "Fix Rejected — No Changes Made"
        outcome_color = "#e74c3c"
        outcome_detail = (
            "The automated fix was rejected by the operator. "
            "No changes were made to the infrastructure."
        )
    else:
        outcome_icon = "⚠️"
        outcome_title = "Fix Failed"
        outcome_color = "#e67e22"
        outcome_detail = (
            f"The automated fix encountered an error.<br>"
            f"Error: {error or ssm_status_text}<br>"
            f"Cause: {cause or ssm_result.get('failure_message', 'See CloudWatch Logs')}"
        )

    template = _TEMPLATE_PATH.read_text(encoding="utf-8")
    html_body = _render_email(template, {
        "outcome_icon": outcome_icon,
        "outcome_title": outcome_title,
        "outcome_color": outcome_color,
        "outcome_detail": outcome_detail,
        "alarm_name": alarm_name,
        "resource_arn": resource_arn,
        "diagnosis": diagnosis,
        "incident_id": incident_id,
        "timestamp": now,
        "environment": ENVIRONMENT.upper(),
    })

    subject = (
        f"[{ENVIRONMENT.upper()}] Self-Healing: {outcome_title} — {alarm_name}"
    )

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
                        f"{outcome_title}\n\n"
                        f"Alarm: {alarm_name}\n"
                        f"Resource: {resource_arn}\n"
                        f"Diagnosis: {diagnosis}\n"
                        f"Status: {final_status}\n"
                        f"Timestamp: {now}\n"
                    ),
                    "Charset": "UTF-8",
                },
            },
        },
    )

    logger.info(
        "Result email sent for incident %s (status=%s)", incident_id, final_status
    )
    return {
        "incident_id": incident_id,
        "result_email_sent": True,
    }
