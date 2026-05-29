output "step_functions_arn" {
  value       = module.step_functions.state_machine_arn
  description = "ARN of the self-healing Step Functions state machine."
}

output "step_functions_name" {
  value       = module.step_functions.state_machine_name
  description = "Name of the self-healing Step Functions state machine."
}

output "dynamodb_table_name" {
  value       = module.dynamodb.table_name
  description = "Name of the DynamoDB incidents table."
}

output "gemini_secret_arn" {
  value       = module.lambdas.gemini_secret_arn
  description = "ARN of the Gemini API key secret — update this after apply with your real key."
}

output "api_gateway_url" {
  value       = module.api_gateway.api_gateway_url
  description = "Base URL for approval callbacks — append /approve or /reject."
}
