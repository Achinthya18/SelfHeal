data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# ── Trust policy shared by all Lambda execution roles ──────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ── DiagnosticLambda ────────────────────────────────────────────────────────
resource "aws_iam_role" "diagnostic_lambda" {
  name               = "diagnostic-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "diagnostic_lambda_basic" {
  role       = aws_iam_role.diagnostic_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "diagnostic_lambda_custom" {
  name = "diagnostic-lambda-policy-${var.environment}"
  role = aws_iam_role.diagnostic_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadCloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:FilterLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:${local.account_id}:log-group:*"
      },
      {
        Sid      = "GetGeminiApiKey"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue"]
        Resource = aws_secretsmanager_secret.gemini_api_key.arn
      }
    ]
  })
}

# ── SendApprovalEmailLambda ─────────────────────────────────────────────────
resource "aws_iam_role" "send_approval_email_lambda" {
  name               = "send-approval-email-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "send_approval_email_lambda_basic" {
  role       = aws_iam_role.send_approval_email_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "send_approval_email_lambda_custom" {
  name = "send-approval-email-lambda-policy-${var.environment}"
  role = aws_iam_role.send_approval_email_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendSESEmail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "arn:aws:ses:${var.aws_region}:${local.account_id}:identity/${var.ses_sender_email}"
      },
      {
        Sid      = "WriteIncidentRecord"
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem"]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# ── ApprovalCallbackLambda ──────────────────────────────────────────────────
resource "aws_iam_role" "approval_callback_lambda" {
  name               = "approval-callback-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "approval_callback_lambda_basic" {
  role       = aws_iam_role.approval_callback_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "approval_callback_lambda_custom" {
  name = "approval-callback-lambda-policy-${var.environment}"
  role = aws_iam_role.approval_callback_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ResumeStepFunctions"
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure"
        ]
        # Scoped to all state machines in this account; tightened when SF module is created
        Resource = "arn:aws:states:${var.aws_region}:${local.account_id}:stateMachine:*"
      },
      {
        Sid    = "ReadUpdateIncidentRecord"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:UpdateItem"
        ]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# ── ExecuteRunbookLambda ────────────────────────────────────────────────────
resource "aws_iam_role" "execute_runbook_lambda" {
  name               = "execute-runbook-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "execute_runbook_lambda_basic" {
  role       = aws_iam_role.execute_runbook_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "execute_runbook_lambda_custom" {
  name = "execute-runbook-lambda-policy-${var.environment}"
  role = aws_iam_role.execute_runbook_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartAndQuerySSM"
        Effect = "Allow"
        Action = [
          "ssm:StartAutomationExecution",
          "ssm:GetAutomationExecution",
        ]
        Resource = "*"
      },
      {
        Sid    = "PassSSMAutomationRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = aws_iam_role.ssm_automation_execution.arn
      },
      {
        Sid      = "UpdateIncidentRecord"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.dynamodb_table_arn
      }
    ]
  })
}

# ── SSM Automation Execution Role ────────────────────────────────────────────
# This role is assumed by the SSM Automation service when executing runbook steps.
resource "aws_iam_role" "ssm_automation_execution" {
  name = "self-healing-ssm-automation-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ssm_automation_execution" {
  name = "self-healing-ssm-automation-policy-${var.environment}"
  role = aws_iam_role.ssm_automation_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECSRunbooks"
        Effect = "Allow"
        Action = [
          "ecs:ListTasks",
          "ecs:StopTask",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition",
          "ecs:RegisterTaskDefinition",
          "ecs:UpdateService",
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Runbooks"
        Effect = "Allow"
        Action = [
          "ec2:StopInstances",
          "ec2:StartInstances",
          "ec2:DescribeInstances",
        ]
        Resource = "*"
      },
      {
        Sid    = "ASGRunbooks"
        Effect = "Allow"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:SetDesiredCapacity",
        ]
        Resource = "*"
      },
      {
        Sid    = "RDSRunbooks"
        Effect = "Allow"
        Action = [
          "rds:ModifyDBInstance",
          "rds:DescribeDBInstances",
        ]
        Resource = "*"
      },
      {
        Sid    = "SecretsManagerRunbooks"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
        ]
        Resource = "*"
      },
      {
        Sid      = "IAMPassRoleForECS"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ecs-tasks.amazonaws.com"
          }
        }
      }
    ]
  })
}

# ── SendResultEmailLambda ───────────────────────────────────────────────────
resource "aws_iam_role" "send_result_email_lambda" {
  name               = "send-result-email-lambda-role-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "send_result_email_lambda_basic" {
  role       = aws_iam_role.send_result_email_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "send_result_email_lambda_custom" {
  name = "send-result-email-lambda-policy-${var.environment}"
  role = aws_iam_role.send_result_email_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SendSESEmail"
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "arn:aws:ses:${var.aws_region}:${local.account_id}:identity/${var.ses_sender_email}"
      },
      {
        Sid      = "UpdateIncidentRecord"
        Effect   = "Allow"
        Action   = ["dynamodb:UpdateItem"]
        Resource = var.dynamodb_table_arn
      },
      {
        Sid      = "GetSSMExecution"
        Effect   = "Allow"
        Action   = ["ssm:GetAutomationExecution"]
        Resource = "*"
      }
    ]
  })
}
