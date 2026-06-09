output "diagnostic_lambda_arn" {
  value       = aws_lambda_function.diagnostic.arn
  description = "ARN of DiagnosticLambda"
}

output "send_approval_email_lambda_arn" {
  value       = aws_lambda_function.send_approval_email.arn
  description = "ARN of SendApprovalEmailLambda"
}

output "approval_callback_lambda_arn" {
  value       = aws_lambda_function.approval_callback.arn
  description = "ARN of ApprovalCallbackLambda"
}

output "execute_runbook_lambda_arn" {
  value       = aws_lambda_function.execute_runbook.arn
  description = "ARN of ExecuteRunbookLambda"
}

output "send_result_email_lambda_arn" {
  value       = aws_lambda_function.send_result_email.arn
  description = "ARN of SendResultEmailLambda"
}

output "diagnostic_lambda_role_arn" {
  value       = aws_iam_role.diagnostic_lambda.arn
  description = "IAM role ARN for DiagnosticLambda"
}

output "send_approval_email_lambda_role_arn" {
  value       = aws_iam_role.send_approval_email_lambda.arn
  description = "IAM role ARN for SendApprovalEmailLambda"
}

output "approval_callback_lambda_role_arn" {
  value       = aws_iam_role.approval_callback_lambda.arn
  description = "IAM role ARN for ApprovalCallbackLambda"
}

output "approval_callback_lambda_name" {
  value       = aws_lambda_function.approval_callback.function_name
  description = "Function name of ApprovalCallbackLambda (used for Lambda permission)"
}

output "send_result_email_lambda_role_arn" {
  value       = aws_iam_role.send_result_email_lambda.arn
  description = "IAM role ARN for SendResultEmailLambda"
}

output "gemini_secret_arn" {
  value       = aws_secretsmanager_secret.gemini_api_key.arn
  description = "ARN of the Gemini API key secret in Secrets Manager"
}

output "function_names" {
  value = {
    diagnostic          = aws_lambda_function.diagnostic.function_name
    send_approval_email = aws_lambda_function.send_approval_email.function_name
    approval_callback   = aws_lambda_function.approval_callback.function_name
    execute_runbook     = aws_lambda_function.execute_runbook.function_name
    send_result_email   = aws_lambda_function.send_result_email.function_name
  }
  description = "Function names of all five Lambdas — consumed by the dashboard module."
}
