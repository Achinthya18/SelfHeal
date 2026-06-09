# ── Self-healing observability dashboard ─────────────────────────────────────
# Single-pane view across every layer of the pipeline. Read-only — no IAM,
# no alarms, no log subscriptions are created here. Each widget is bound to
# resources passed in via variables so the dashboard is locked to the same
# environment as the rest of the stack.

locals {
  region = var.aws_region
  sfn    = var.state_machine_arn

  lambda_names = [
    var.lambda_function_names.diagnostic,
    var.lambda_function_names.send_approval_email,
    var.lambda_function_names.approval_callback,
    var.lambda_function_names.execute_runbook,
    var.lambda_function_names.send_result_email,
  ]

  dashboard_body = jsonencode({
    widgets = [
      # ── Row 1: Step Functions pipeline counters ────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 24
        height = 6
        properties = {
          title   = "Step Functions — pipeline executions"
          region  = local.region
          view    = "timeSeries"
          stacked = false
          stat    = "Sum"
          period  = 300
          metrics = [
            ["AWS/States", "ExecutionsStarted", "StateMachineArn", local.sfn],
            [".", "ExecutionsSucceeded", ".", "."],
            [".", "ExecutionsFailed", ".", "."],
            [".", "ExecutionsTimedOut", ".", "."],
            [".", "ExecutionsAborted", ".", "."],
          ]
        }
      },

      # ── Row 2 left: Lambda invocations ─────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — invocations"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            for fn in local.lambda_names :
            ["AWS/Lambda", "Invocations", "FunctionName", fn]
          ]
        }
      },

      # ── Row 2 right: Lambda errors + throttles ────────────────────────────
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda — errors + throttles"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = concat(
            [for fn in local.lambda_names : ["AWS/Lambda", "Errors", "FunctionName", fn]],
            [for fn in local.lambda_names : [".", "Throttles", ".", fn]],
          )
        }
      },

      # ── Row 3: Lambda p95 duration ────────────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 24
        height = 6
        properties = {
          title  = "Lambda — duration (p95, ms)"
          region = local.region
          view   = "timeSeries"
          stat   = "p95"
          period = 300
          metrics = [
            for fn in local.lambda_names :
            ["AWS/Lambda", "Duration", "FunctionName", fn]
          ]
        }
      },

      # ── Row 4 left: DynamoDB incidents table ──────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "DynamoDB — incidents table"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", var.dynamodb_table_name],
            [".", "ConsumedWriteCapacityUnits", ".", "."],
            [".", "UserErrors", ".", "."],
          ]
        }
      },

      # ── Row 4 right: SES (account-level) ──────────────────────────────────
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          title  = "SES — email outcomes (account-level)"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/SES", "Send"],
            [".", "Delivery"],
            [".", "Bounce"],
            [".", "Complaint"],
            [".", "Reject"],
          ]
        }
      },

      # ── Row 5: API Gateway (approval API) ─────────────────────────────────
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 24
        height = 6
        properties = {
          title  = "API Gateway — approval callbacks"
          region = local.region
          view   = "timeSeries"
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiName", var.api_gateway_name, "Stage", var.api_gateway_stage],
            [".", "4XXError", ".", ".", ".", "."],
            [".", "5XXError", ".", ".", ".", "."],
          ]
        }
      },

      # ── Row 6: Alarm states ───────────────────────────────────────────────
      {
        type   = "alarm"
        x      = 0
        y      = 30
        width  = 24
        height = 4
        properties = {
          title = "Pipeline alarms — current state"
          alarms = [
            for name in var.alarm_names :
            "arn:aws:cloudwatch:${local.region}:${data.aws_caller_identity.current.account_id}:alarm:${name}"
          ]
        }
      },
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_dashboard" "self_healing" {
  dashboard_name = "self-healing-${var.environment}"
  dashboard_body = local.dashboard_body
}
