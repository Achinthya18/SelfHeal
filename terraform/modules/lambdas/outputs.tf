output "diagnostic_lambda_role_arn" {
  description = "IAM role ARN for DiagnosticLambda"
  value       = aws_iam_role.diagnostic_lambda.arn
}

output "send_approval_email_lambda_role_arn" {
  description = "IAM role ARN for SendApprovalEmailLambda"
  value       = aws_iam_role.send_approval_email_lambda.arn
}

output "approval_callback_lambda_role_arn" {
  description = "IAM role ARN for ApprovalCallbackLambda"
  value       = aws_iam_role.approval_callback_lambda.arn
}

output "send_result_email_lambda_role_arn" {
  description = "IAM role ARN for SendResultEmailLambda"
  value       = aws_iam_role.send_result_email_lambda.arn
}

output "gemini_secret_arn" {
  description = "ARN of the Gemini API key secret in Secrets Manager"
  value       = aws_secretsmanager_secret.gemini_api_key.arn
}
