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

variable "approval_token_expiry_minutes" {
  description = "Minutes before approval token expires"
  type        = number
  default     = 15
}
