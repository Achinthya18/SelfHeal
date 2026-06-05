locals {
  lambda_runtime = "python3.11"
  lambda_files   = "${path.module}/files"
}

# ── Dependency install: requests library for DiagnosticLambda ──────────────
resource "null_resource" "install_diagnostic_deps" {
  triggers = {
    requirements_hash = filemd5("${path.module}/../../../lambdas/diagnostic/requirements.txt")
  }

  provisioner "local-exec" {
    command     = "python -m pip install requests -t . --upgrade --quiet"
    working_dir = "${path.module}/../../../lambdas/diagnostic"
  }
}

# ── Lambda package archives ─────────────────────────────────────────────────
data "archive_file" "diagnostic" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/diagnostic"
  output_path = "${local.lambda_files}/diagnostic.zip"
  depends_on  = [null_resource.install_diagnostic_deps]
}

data "archive_file" "send_approval_email" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/send_approval_email"
  output_path = "${local.lambda_files}/send_approval_email.zip"
}

data "archive_file" "approval_callback" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/approval_callback"
  output_path = "${local.lambda_files}/approval_callback.zip"
}

data "archive_file" "execute_runbook" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/execute_runbook"
  output_path = "${local.lambda_files}/execute_runbook.zip"
}

data "archive_file" "send_result_email" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/send_result_email"
  output_path = "${local.lambda_files}/send_result_email.zip"
}

# ── Lambda functions ────────────────────────────────────────────────────────
resource "aws_lambda_function" "diagnostic" {
  filename         = data.archive_file.diagnostic.output_path
  source_code_hash = data.archive_file.diagnostic.output_base64sha256
  function_name    = "diagnostic-lambda-${var.environment}"
  role             = aws_iam_role.diagnostic_lambda.arn
  handler          = "handler.handler"
  runtime          = local.lambda_runtime
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      GEMINI_SECRET_ARN = aws_secretsmanager_secret.gemini_api_key.arn
      GEMINI_MODEL_ID   = var.gemini_model_id
      LOG_LEVEL         = "INFO"
      ENVIRONMENT       = var.environment
    }
  }
}

resource "aws_lambda_function" "send_approval_email" {
  filename         = data.archive_file.send_approval_email.output_path
  source_code_hash = data.archive_file.send_approval_email.output_base64sha256
  function_name    = "send-approval-email-lambda-${var.environment}"
  role             = aws_iam_role.send_approval_email_lambda.arn
  handler          = "handler.handler"
  runtime          = local.lambda_runtime
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      SES_SENDER_EMAIL              = var.ses_sender_email
      SES_RECIPIENT_EMAIL           = var.ses_recipient_email
      API_GATEWAY_BASE_URL          = var.api_gateway_base_url
      APPROVAL_TOKEN_SECRET         = var.approval_token_secret
      APPROVAL_TOKEN_EXPIRY_MINUTES = tostring(var.approval_token_expiry_minutes)
      DYNAMO_TABLE_NAME             = "self-healing-incidents"
      LOG_LEVEL                     = "INFO"
      ENVIRONMENT                   = var.environment
    }
  }
}

resource "aws_lambda_function" "approval_callback" {
  filename         = data.archive_file.approval_callback.output_path
  source_code_hash = data.archive_file.approval_callback.output_base64sha256
  function_name    = "approval-callback-lambda-${var.environment}"
  role             = aws_iam_role.approval_callback_lambda.arn
  handler          = "handler.handler"
  runtime          = local.lambda_runtime
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      APPROVAL_TOKEN_SECRET = var.approval_token_secret
      DYNAMO_TABLE_NAME     = "self-healing-incidents"
      LOG_LEVEL             = "INFO"
      ENVIRONMENT           = var.environment
    }
  }
}

resource "aws_lambda_function" "execute_runbook" {
  filename         = data.archive_file.execute_runbook.output_path
  source_code_hash = data.archive_file.execute_runbook.output_base64sha256
  function_name    = "execute-runbook-lambda-${var.environment}"
  role             = aws_iam_role.execute_runbook_lambda.arn
  handler          = "handler.handler"
  runtime          = local.lambda_runtime
  timeout          = 840 # 14 min — SSM runbooks can take up to 12 min
  memory_size      = 128

  environment {
    variables = {
      SSM_AUTOMATION_ROLE_ARN = aws_iam_role.ssm_automation_execution.arn
      DYNAMO_TABLE_NAME       = "self-healing-incidents"
      LOG_LEVEL               = "INFO"
      ENVIRONMENT             = var.environment
    }
  }
}

resource "aws_lambda_function" "send_result_email" {
  filename         = data.archive_file.send_result_email.output_path
  source_code_hash = data.archive_file.send_result_email.output_base64sha256
  function_name    = "send-result-email-lambda-${var.environment}"
  role             = aws_iam_role.send_result_email_lambda.arn
  handler          = "handler.handler"
  runtime          = local.lambda_runtime
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      SES_SENDER_EMAIL    = var.ses_sender_email
      SES_RECIPIENT_EMAIL = var.ses_recipient_email
      DYNAMO_TABLE_NAME   = "self-healing-incidents"
      LOG_LEVEL           = "INFO"
      ENVIRONMENT         = var.environment
    }
  }
}
