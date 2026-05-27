"""
dynamo_client.py — DynamoDB helpers for the approval_callback Lambda.
"""

import logging
import os

import boto3
from boto3.dynamodb.conditions import Key

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME", "self-healing-incidents")

_table = None


def _get_table():
    global _table
    if _table is None:
        dynamodb = boto3.resource("dynamodb")
        _table = dynamodb.Table(TABLE_NAME)
    return _table


def get_incident(incident_id: str, created_at: str) -> dict | None:
    """Fetch incident by primary key."""
    table = _get_table()
    response = table.get_item(
        Key={"incident_id": incident_id, "created_at": created_at}
    )
    return response.get("Item")


def update_incident_status(
    incident_id: str,
    created_at: str,
    status: str,
    extra: dict | None = None,
) -> None:
    """
    Update the status of an incident and optionally set extra attributes.

    Parameters
    ----------
    incident_id : str
    created_at : str
    status : str
        New status value (approved / rejected / resolved / failed).
    extra : dict | None
        Additional key-value pairs to set (e.g., {"approved_at": "..."}).
    """
    table = _get_table()
    extra = extra or {}

    update_expr = "SET #s = :status"
    expr_names = {"#s": "status"}
    expr_values = {":status": status}

    for k, v in extra.items():
        safe_key = f"#{k}"
        expr_names[safe_key] = k
        expr_values[f":{k}"] = v
        update_expr += f", {safe_key} = :{k}"

    logger.info(
        "Updating incident %s status → %s (extra keys: %s)",
        incident_id, status, list(extra.keys())
    )
    table.update_item(
        Key={"incident_id": incident_id, "created_at": created_at},
        UpdateExpression=update_expr,
        ExpressionAttributeNames=expr_names,
        ExpressionAttributeValues=expr_values,
    )
