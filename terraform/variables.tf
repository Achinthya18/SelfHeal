variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (dev or prod)"
  type        = string
  default     = "dev"
}

variable "ses_sender_email" {
  description = "Verified SES email address used to send approval and result emails"
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

variable "approval_token_expiry_minutes" {
  description = "Minutes before an approval link expires"
  type        = number
  default     = 15
}

variable "approval_token_secret" {
  description = "Secret key used to sign and verify approval tokens embedded in SES emails"
  type        = string
  sensitive   = true
}
