"""
cloudwatch_client.py — fetches recent log events from a CloudWatch Logs group.
"""

import logging
import os
import time

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

_logs_client = None


def _get_client():
    global _logs_client
    if _logs_client is None:
        _logs_client = boto3.client("logs")
    return _logs_client


def get_recent_logs(
    log_group_name: str,
    minutes: int = 30,
    limit: int = 100,
) -> list[str]:
    """
    Return up to `limit` recent log event messages from `log_group_name`.

    Events are returned oldest-first.  Each element is a plain string
    (the `message` field from the CloudWatch log event, stripped of
    leading/trailing whitespace).

    Parameters
    ----------
    log_group_name : str
        Full CloudWatch log group name, e.g. ``/ecs/my-service``.
    minutes : int
        How far back to search in minutes (default 30).
    limit : int
        Maximum number of log lines to return (default 100).

    Returns
    -------
    list[str]
        Ordered list of log message strings.  Empty list if no events found
        or the log group does not exist.
    """
    client = _get_client()
    end_time_ms = int(time.time() * 1000)
    start_time_ms = end_time_ms - (minutes * 60 * 1000)

    logger.info(
        "Fetching up to %d log events from '%s' (last %d minutes)",
        limit,
        log_group_name,
        minutes,
    )

    try:
        paginator = client.get_paginator("filter_log_events")
        pages = paginator.paginate(
            logGroupName=log_group_name,
            startTime=start_time_ms,
            endTime=end_time_ms,
            PaginationConfig={"MaxItems": limit, "PageSize": min(limit, 100)},
        )

        events: list[str] = []
        for page in pages:
            for event in page.get("events", []):
                msg = event.get("message", "").strip()
                if msg:
                    events.append(msg)
                if len(events) >= limit:
                    break
            if len(events) >= limit:
                break

    except client.exceptions.ResourceNotFoundException:
        logger.warning("Log group '%s' not found — returning empty list", log_group_name)
        return []
    except Exception as exc:
        logger.error("Error fetching logs from '%s': %s", log_group_name, exc)
        raise

    logger.info("Fetched %d log events from '%s'", len(events), log_group_name)
    return events


def format_logs_for_prompt(events: list[str]) -> str:
    """
    Join log lines into a single string suitable for embedding in a prompt.

    Lines are numbered so Gemini can reference specific lines in its reasoning.
    """
    if not events:
        return "(no log events found in the last 30 minutes)"
    numbered = "\n".join(f"{i + 1:>4}: {line}" for i, line in enumerate(events))
    return f"```\n{numbered}\n```"
