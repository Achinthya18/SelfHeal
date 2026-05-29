"""
ApprovalCallbackLambda — handler.py

Triggered by API Gateway when a human clicks the Approve or Reject link
in the SES email.

Query parameters (GET or POST):
    incident_id  — UUID of the incident
    created_at   — ISO 8601 sort key (needed for DynamoDB GetItem)
    token        — HMAC-signed approval token
    task_token   — Step Functions task token (URL-encoded)
    action       — "approve" or "reject" (derived from the URL path)

The action (approve vs reject) is determined by the API Gateway route:
    POST /approve  → action = "approve"
    POST /reject   → action = "reject"
The handler reads the path from the API Gateway event to determine the action.
"""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone

import boto3

from dynamo_client import get_incident, update_incident_status
from token_validator import TokenExpiredError, TokenInvalidError, validate_token

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

_sf_client = None


def _get_sf():
    global _sf_client
    if _sf_client is None:
        _sf_client = boto3.client("stepfunctions")
    return _sf_client


def _html_response(status_code: int, title: str, message: str, color: str = "#2c3e50") -> dict:
    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{title}</title>
  <style>
    body {{ font-family: -apple-system, sans-serif; display: flex; align-items: center;
            justify-content: center; min-height: 100vh; margin: 0; background: #f4f6f8; }}
    .card {{ max-width: 480px; background: #fff; border-radius: 10px; padding: 40px;
             box-shadow: 0 4px 16px rgba(0,0,0,0.10); text-align: center; }}
    h1 {{ color: {color}; font-size: 28px; margin-bottom: 12px; }}
    p {{ color: #555; font-size: 16px; line-height: 1.6; }}
  </style>
</head>
<body>
  <div class="card">
    <h1>{title}</h1>
    <p>{message}</p>
  </div>
</body>
</html>"""
    return {
        "statusCode": status_code,
        "headers": {"Content-Type": "text/html; charset=utf-8"},
        "body": html,
    }


def handler(event: dict, context) -> dict:
    logger.info("ApprovalCallbackLambda invoked: %s", json.dumps(event))

    # ── Parse query parameters ──────────────────────────────────────────────
    params = event.get("queryStringParameters") or {}
    incident_id = params.get("incident_id", "")
    created_at = params.get("created_at", "")
    token = params.get("token", "")
    task_token = params.get("task_token", "")

    # URL-decode params — API Gateway usually decodes these, but be explicit
    created_at = urllib.parse.unquote(created_at)
    task_token = urllib.parse.unquote(task_token)

    # ── Determine action from the resource path ─────────────────────────────
    path = event.get("path", event.get("rawPath", "/approve"))
    action = "approve" if "/approve" in path else "reject"
    logger.info("Action=%s incident_id=%s", action, incident_id)

    # ── Validate required params ────────────────────────────────────────────
    if not all([incident_id, created_at, token, task_token]):
        return _html_response(
            400, "Invalid Request",
            "This link is missing required parameters. Please check your email.",
            "#e74c3c"
        )

    # ── Validate token ──────────────────────────────────────────────────────
    try:
        validate_token(token, incident_id)
    except TokenExpiredError:
        return _html_response(
            410, "⏱ Link Expired",
            "This approval link has expired. No changes have been made to your infrastructure. "
            "If the issue is still ongoing, a new alert will be sent automatically.",
            "#e67e22"
        )
    except TokenInvalidError:
        return _html_response(
            403, "Invalid Link",
            "This link is not valid. No changes have been made.",
            "#e74c3c"
        )

    # ── Fetch incident from DynamoDB ────────────────────────────────────────
    incident = get_incident(incident_id, created_at)
    if not incident:
        return _html_response(
            404, "Incident Not Found",
            "Could not find the incident record. It may have expired or been deleted.",
            "#7f8c8d"
        )

    if incident.get("status") not in ("pending",):
        return _html_response(
            409, "Already Processed",
            f"This incident has already been {incident.get('status')}. "
            "No further action is needed.",
            "#7f8c8d"
        )

    # ── Send task callback to Step Functions ────────────────────────────────
    now = datetime.now(timezone.utc).isoformat()
    sf = _get_sf()

    if action == "approve":
        sf.send_task_success(
            taskToken=task_token,
            output=json.dumps({
                "incident_id": incident_id,
                "created_at": created_at,
                "action": "approved",
                "approved_at": now,
                "recommended_runbook": incident.get("recommended_runbook"),
                "resource_arn": incident.get("resource_arn"),
            }),
        )
        update_incident_status(
            incident_id, created_at,
            status="approved",
            extra={"approved_at": now},
        )
        return _html_response(
            200, "✅ Fix Approved",
            f"Your approval has been received. The runbook "
            f"<strong>{incident.get('recommended_runbook')}</strong> is now executing. "
            f"You will receive a confirmation email when it completes.",
            "#27ae60"
        )

    else:  # reject
        sf.send_task_failure(
            taskToken=task_token,
            error="HumanRejected",
            cause=f"Human rejected the fix for incident {incident_id} at {now}",
        )
        update_incident_status(
            incident_id, created_at,
            status="rejected",
            extra={"rejected_at": now},
        )
        return _html_response(
            200, "❌ Fix Rejected",
            "You have chosen not to apply the automated fix. "
            "No changes have been made to your infrastructure.",
            "#e74c3c"
        )
