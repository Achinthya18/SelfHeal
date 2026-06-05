# ── IAM role: allow EventBridge to start Step Functions executions ────────────
resource "aws_iam_role" "eventbridge_sfn" {
  name = "self-healing-eventbridge-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_sfn" {
  name = "start-step-functions-${var.environment}"
  role = aws_iam_role.eventbridge_sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["states:StartExecution"]
      Resource = [var.step_functions_arn]
    }]
  })
}

# ── EventBridge rule: catch any self-healing alarm going to ALARM state ───────
resource "aws_cloudwatch_event_rule" "alarm_to_alarm" {
  name        = "self-healing-alarm-trigger-${var.environment}"
  description = "Routes CloudWatch ALARM state changes (self-healing-* alarms) to Step Functions"

  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail = {
      state = {
        value = ["ALARM"]
      }
      alarmName = [{ prefix = "self-healing-" }]
    }
  })
}

# ── EventBridge target: Step Functions state machine ─────────────────────────
resource "aws_cloudwatch_event_target" "step_functions" {
  rule      = aws_cloudwatch_event_rule.alarm_to_alarm.name
  target_id = "SelfHealingStateMachine"
  arn       = var.step_functions_arn
  role_arn  = aws_iam_role.eventbridge_sfn.arn

  # Build the Step Functions input from the CloudWatch alarm event.
  # resource_arn is set to the alarm ARN as a placeholder; DiagnosticLambda
  # already handles cases where the resource ARN has no matching log group.
  # When the alarm has ECS dimensions (ClusterName + ServiceName) the transformer
  # builds a proper ECS service ARN that ExecuteRunbook can parse. For alarms
  # without those dimensions (e.g. the manual-test alarm), the cluster/service
  # placeholders resolve to empty strings — those paths were never expected to
  # complete a real ECS restart anyway, and the upstream pipeline still works.
  input_transformer {
    input_paths = {
      alarm_name  = "$.detail.alarmName"
      alarm_arn   = "$.resources[0]"
      reason      = "$.detail.state.reason"
      region      = "$.region"
      account     = "$.account"
      ecs_cluster = "$.detail.configuration.metrics[0].metricStat.metric.dimensions.ClusterName"
      ecs_service = "$.detail.configuration.metrics[0].metricStat.metric.dimensions.ServiceName"
    }
    input_template = <<-JSON
      {
        "alarm_name":     "<alarm_name>",
        "alarm_arn":      "<alarm_arn>",
        "resource_arn":   "arn:aws:ecs:<region>:<account>:service/<ecs_cluster>/<ecs_service>",
        "log_group_name": "/self-healing/demo-service",
        "reason":         "<reason>",
        "region":         "<region>"
      }
    JSON
  }
}
