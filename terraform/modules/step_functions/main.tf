# ── IAM role for Step Functions ─────────────────────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "self-healing-step-functions-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "step_functions_invoke_lambda" {
  name = "invoke-lambdas-${var.environment}"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "InvokeLambdas"
      Effect = "Allow"
      Action = ["lambda:InvokeFunction"]
      Resource = [
        var.diagnostic_lambda_arn,
        var.send_approval_email_lambda_arn,
        var.execute_runbook_lambda_arn,
        var.send_result_email_lambda_arn,
      ]
    }]
  })
}

# ── State machine definition ─────────────────────────────────────────────────
locals {
  state_machine_definition = jsonencode({
    Comment = "Self-Healing Infrastructure: diagnose → email approval → HITL wait → execute runbook → email result"
    StartAt = "RunDiagnostic"
    States = {

      RunDiagnostic = {
        Type     = "Task"
        Comment  = "Fetch CloudWatch logs and call Gemini to diagnose the alarm."
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = var.diagnostic_lambda_arn
          "Payload.$"    = "$"
        }
        ResultSelector = {
          "incident_id.$"        = "$.Payload.incident_id"
          "created_at.$"         = "$.Payload.created_at"
          "alarm_name.$"         = "$.Payload.alarm_name"
          "alarm_arn.$"          = "$.Payload.alarm_arn"
          "resource_arn.$"       = "$.Payload.resource_arn"
          "log_group_name.$"     = "$.Payload.log_group_name"
          "logs_snapshot.$"      = "$.Payload.logs_snapshot"
          "diagnosis.$"          = "$.Payload.diagnosis"
          "recommended_runbook.$" = "$.Payload.recommended_runbook"
          "confidence.$"         = "$.Payload.confidence"
          "reasoning.$"          = "$.Payload.reasoning"
        }
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error_info"
          Next        = "HandleError"
        }]
        Next = "SendApprovalEmail"
      }

      SendApprovalEmail = {
        Type    = "Task"
        Comment = "Send SES approval email; pause execution until human clicks Approve or Reject (up to 24 h)."
        Resource = "arn:aws:states:::lambda:invoke.waitForTaskToken"
        Parameters = {
          "FunctionName" = var.send_approval_email_lambda_arn
          Payload = {
            "incident_id.$"         = "$.incident_id"
            "created_at.$"          = "$.created_at"
            "alarm_name.$"          = "$.alarm_name"
            "alarm_arn.$"           = "$.alarm_arn"
            "resource_arn.$"        = "$.resource_arn"
            "log_group_name.$"      = "$.log_group_name"
            "logs_snapshot.$"       = "$.logs_snapshot"
            "diagnosis.$"           = "$.diagnosis"
            "recommended_runbook.$" = "$.recommended_runbook"
            "confidence.$"          = "$.confidence"
            "reasoning.$"           = "$.reasoning"
            "taskToken.$"           = "$$.Task.Token"
          }
        }
        HeartbeatSeconds = 86400
        ResultPath       = "$.approval_callback"
        Catch = [
          {
            ErrorEquals = ["HumanRejected"]
            ResultPath  = "$.error_info"
            Next        = "HandleError"
          },
          {
            ErrorEquals = ["States.ALL"]
            ResultPath  = "$.error_info"
            Next        = "HandleError"
          }
        ]
        Next = "ExecuteRunbook"
      }

      ExecuteRunbook = {
        Type     = "Task"
        Comment  = "Trigger the SSM Automation runbook selected by Gemini and wait for it to complete."
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = var.execute_runbook_lambda_arn
          "Payload.$"    = "$"
        }
        ResultSelector = {
          "incident_id.$"         = "$.Payload.incident_id"
          "created_at.$"          = "$.Payload.created_at"
          "alarm_name.$"          = "$.Payload.alarm_name"
          "resource_arn.$"        = "$.Payload.resource_arn"
          "recommended_runbook.$" = "$.Payload.recommended_runbook"
          "diagnosis.$"           = "$.Payload.diagnosis"
          "ssm_execution_id.$"    = "$.Payload.ssm_execution_id"
          "ssm_status.$"          = "$.Payload.ssm_status"
          "action.$"              = "$.Payload.action"
        }
        Catch = [{
          ErrorEquals = ["States.ALL"]
          ResultPath  = "$.error_info"
          Next        = "HandleError"
        }]
        Next = "SendResultEmail"
      }

      SendResultEmail = {
        Type     = "Task"
        Comment  = "Email the operator the runbook outcome (resolved or failed)."
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = var.send_result_email_lambda_arn
          "Payload.$"    = "$"
        }
        ResultPath = null
        End        = true
      }

      HandleError = {
        Type     = "Task"
        Comment  = "Error and rejection path — email the operator with failure or rejection details."
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          "FunctionName" = var.send_result_email_lambda_arn
          "Payload.$"    = "$"
        }
        ResultPath = null
        End        = true
      }
    }
  })
}

# ── State machine resource ───────────────────────────────────────────────────
resource "aws_sfn_state_machine" "self_healing" {
  name       = "self-healing-workflow-${var.environment}"
  role_arn   = aws_iam_role.step_functions.arn
  definition = local.state_machine_definition

  tags = {
    Environment = var.environment
  }
}
