variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)."
}

variable "aws_region" {
  type        = string
  description = "AWS region."
}

variable "approval_callback_lambda_arn" {
  type        = string
  description = "ARN of ApprovalCallbackLambda."
}

variable "approval_callback_lambda_name" {
  type        = string
  description = "Name of ApprovalCallbackLambda (used for the Lambda permission resource)."
}
