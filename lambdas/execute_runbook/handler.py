"""
ExecuteRunbookLambda — handler.py

State 3 of the Step Functions workflow (runs after human approval).

Input: the full state dict, which after RunDiagnostic + SendApprovalEmail contains:
{
    "incident_id": "...",
    "created_at": "...",
    "alarm_name": "...",
    "resource_arn": "arn:aws:ecs:...:service/cluster/svc",   # or EC2, ASG, RDS
    "recommended_runbook": "restart_ecs_task",
    "diagnosis": "...",
    "approval_callback": {
        "action": "approved",
        "approved_at": "...",
        ...
    },
    # optional fields for specific runbooks:
    "secret_arn": "arn:aws:secretsmanager:...",   # rotate_rds_password only
    "new_memory_mb": "2048"                        # increase_ecs_memory only
}

Output: a flat dict that SendResultEmailLambda can consume directly:
{
    "incident_id": "...",
    "created_at": "...",
    "alarm_name": "...",
    "resource_arn": "...",
    "recommended_runbook": "...",
    "diagnosis": "...",
    "ssm_execution_id": "...",
    "ssm_status": "Success|Failed|Cancelled|TimedOut",
    "action": "approved"
}
"""

import json
import logging
import os
import time

import boto3

logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

SSM_AUTOMATION_ROLE_ARN = os.environ["SSM_AUTOMATION_ROLE_ARN"]
DYNAMO_TABLE_NAME = os.environ.get("DYNAMO_TABLE_NAME", "self-healing-incidents")

_ssm_client = None
_dynamo_client = None

RUNBOOK_DOCUMENT_MAP = {
    "restart_ecs_task": "self-healing-restart-ecs-task",
    "restart_ec2_instance": "self-healing-restart-ec2-instance",
    "scale_out_asg": "self-healing-scale-out-asg",
    "rotate_rds_password": "self-healing-rotate-rds-password",
    "increase_ecs_memory": "self-healing-increase-ecs-memory",
}

_TERMINAL_STATES = {"Success", "Failed", "Cancelled", "TimedOut", "Cancelling"}
_MAX_WAIT_SECONDS = 720   # 12 min — Lambda timeout is 14 min
_POLL_INTERVAL = 15


def _ssm():
    global _ssm_client
    if _ssm_client is None:
        _ssm_client = boto3.client("ssm")
    return _ssm_client


def _dynamo():
    global _dynamo_client
    if _dynamo_client is None:
        _dynamo_client = boto3.resource("dynamodb")
    return _dynamo_client


def _build_ssm_parameters(runbook: str, resource_arn: str, event: dict) -> dict:
    """
    Map runbook + resource_arn to the parameter dict expected by each SSM document.
    SSM Automation parameters must be a dict of str → list[str].
    """
    if runbook in ("restart_ecs_task", "increase_ecs_memory"):
        # arn:aws:ecs:region:account:service/cluster-name/service-name
        arn_resource = resource_arn.split(":")[-1]         # "service/cluster/svc"
        parts = arn_resource.split("/")                    # ["service", "cluster", "svc"]
        cluster = parts[1] if len(parts) > 1 else arn_resource
        service = parts[2] if len(parts) > 2 else arn_resource
        if runbook == "restart_ecs_task":
            return {"ClusterName": [cluster], "ServiceName": [service]}
        return {
            "ClusterName": [cluster],
            "ServiceName": [service],
            "NewMemoryMb": [str(event.get("new_memory_mb", "2048"))],
        }

    if runbook == "restart_ec2_instance":
        # arn:aws:ec2:region:account:instance/i-xxxxxxxxxx  OR  just "i-xxx"
        instance_id = resource_arn.split("/")[-1]
        return {"InstanceId": [instance_id]}

    if runbook == "scale_out_asg":
        # arn:aws:autoscaling:...:autoScalingGroup:uuid:autoScalingGroupName/name
        if "autoScalingGroupName/" in resource_arn:
            asg_name = resource_arn.split("autoScalingGroupName/")[-1]
        elif "/" in resource_arn:
            asg_name = resource_arn.split("/")[-1]
        else:
            asg_name = resource_arn
        return {"AutoScalingGroupName": [asg_name]}

    if runbook == "rotate_rds_password":
        # arn:aws:rds:region:account:db:dbname
        db_id = resource_arn.split(":")[-1]
        secret_arn = event.get("secret_arn", "")
        if not secret_arn:
            raise ValueError(
                "rotate_rds_password requires a 'secret_arn' field in the Step Functions input"
            )
        return {"DbInstanceId": [db_id], "SecretArn": [secret_arn]}

    raise ValueError(f"Unknown runbook: {runbook!r}")


def _start_automation(document_name: str, parameters: dict) -> str:
    """Start SSM Automation and return the execution ID."""
    response = _ssm().start_automation_execution(
        DocumentName=document_name,
        Parameters=parameters,
        AutomationAssumeRoleArn=SSM_AUTOMATION_ROLE_ARN,
        Tags=[
            {"Key": "Project", "Value": "self-healing-infra"},
            {"Key": "ManagedBy", "Value": "execute-runbook-lambda"},
        ],
    )
    return response["AutomationExecutionId"]


def _wait_for_completion(execution_id: str) -> str:
    """Poll SSM until the execution reaches a terminal state. Returns the final status."""
    iterations = _MAX_WAIT_SECONDS // _POLL_INTERVAL
    for _ in range(iterations):
        resp = _ssm().get_automation_execution(AutomationExecutionId=execution_id)
        status = resp["AutomationExecution"]["AutomationExecutionStatus"]
        logger.info("SSM execution %s status: %s", execution_id, status)
        if status in _TERMINAL_STATES:
            return status
        time.sleep(_POLL_INTERVAL)

    logger.error("SSM execution %s did not complete in %ds", execution_id, _MAX_WAIT_SECONDS)
    return "TimedOut"


def _update_dynamo(incident_id: str, created_at: str, ssm_id: str, ssm_status: str) -> None:
    """Write ssm_execution_id to the DynamoDB incident record."""
    try:
        table = _dynamo().Table(DYNAMO_TABLE_NAME)
        table.update_item(
            Key={"incident_id": incident_id, "created_at": created_at},
            UpdateExpression="SET ssm_execution_id = :eid, #st = :status",
            ExpressionAttributeNames={"#st": "status"},
            ExpressionAttributeValues={
                ":eid": ssm_id,
                ":status": "resolved" if ssm_status == "Success" else "failed",
            },
        )
    except Exception as exc:
        logger.warning("DynamoDB update failed (non-fatal): %s", exc)


def handler(event: dict, context) -> dict:
    logger.info("ExecuteRunbookLambda invoked: %s", json.dumps(event, default=str))

    incident_id = event.get("incident_id", "unknown")
    created_at = event.get("created_at", "")
    alarm_name = event.get("alarm_name", "unknown")
    resource_arn = event.get("resource_arn", "")
    recommended_runbook = event.get("recommended_runbook", "")
    diagnosis = event.get("diagnosis", "")
    action = event.get("approval_callback", {}).get("action", "approved")

    if recommended_runbook not in RUNBOOK_DOCUMENT_MAP:
        raise ValueError(f"Unsupported runbook: {recommended_runbook!r}")

    document_name = RUNBOOK_DOCUMENT_MAP[recommended_runbook]
    parameters = _build_ssm_parameters(recommended_runbook, resource_arn, event)

    logger.info(
        "Starting SSM Automation: document=%s params=%s incident=%s",
        document_name, parameters, incident_id,
    )

    execution_id = _start_automation(document_name, parameters)
    logger.info("SSM execution started: %s", execution_id)

    ssm_status = _wait_for_completion(execution_id)
    logger.info("SSM execution %s finished: %s", execution_id, ssm_status)

    _update_dynamo(incident_id, created_at, execution_id, ssm_status)

    return {
        "incident_id": incident_id,
        "created_at": created_at,
        "alarm_name": alarm_name,
        "resource_arn": resource_arn,
        "recommended_runbook": recommended_runbook,
        "diagnosis": diagnosis,
        "ssm_execution_id": execution_id,
        "ssm_status": ssm_status,
        "action": action,
    }
