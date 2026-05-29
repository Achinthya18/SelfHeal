variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)."
}

variable "aws_region" {
  type        = string
  description = "AWS region."
}

variable "diagnostic_lambda_arn" {
  type        = string
  description = "ARN of DiagnosticLambda."
}

variable "send_approval_email_lambda_arn" {
  type        = string
  description = "ARN of SendApprovalEmailLambda."
}

variable "execute_runbook_lambda_arn" {
  type        = string
  description = "ARN of ExecuteRunbookLambda."
}

variable "send_result_email_lambda_arn" {
  type        = string
  description = "ARN of SendResultEmailLambda."
}
