"""
dynamo_client.py — shared DynamoDB helpers used by send_approval_email Lambda.
"""

import logging
import os

import boto3

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


def save_incident(incident: dict) -> None:
    """
    Write a new incident record to DynamoDB.

    The dict must contain at minimum:
        incident_id (str)   — partition key
        created_at  (str)   — sort key (ISO 8601)
        ttl         (int)   — Unix timestamp 90 days from now

    Raises on write failure (let it propagate so Step Functions retries).
    """
    table = _get_table()
    logger.info("Saving incident %s to DynamoDB", incident.get("incident_id"))
    table.put_item(Item=incident)
    logger.info("Incident %s saved", incident.get("incident_id"))
