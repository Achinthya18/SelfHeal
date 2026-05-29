variable "environment" {
  description = "Deployment environment"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the incidents DynamoDB table"
  type        = string
}

variable "ses_sender_email" {
  description = "Verified SES sender email address"
  type        = string
}

variable "ses_recipient_email" {
  description = "Email address that receives approval and result emails"
  type        = string
}

variable "gemini_model_id" {
  description = "Gemini model ID used by DiagnosticLambda"
  type        = string
  default     = "gemini-2.5-flash"
}

variable "approval_token_secret" {
  description = "Secret used to sign and verify approval tokens in SES emails"
  type        = string
  sensitive   = true
}

variable "approval_token_expiry_minutes" {
  description = "Minutes before an approval link expires"
  type        = number
  default     = 15
}

variable "api_gateway_base_url" {
  description = "Base URL of the API Gateway (populated in Phase 6; use empty string until then)"
  type        = string
  default     = ""
}
