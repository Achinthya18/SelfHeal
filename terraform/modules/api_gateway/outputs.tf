output "api_gateway_url" {
  value       = "https://${aws_api_gateway_rest_api.self_healing.id}.execute-api.${var.aws_region}.amazonaws.com/${aws_api_gateway_stage.v1.stage_name}"
  description = "Base URL of the approval API — append /approve or /reject."
}

output "api_gateway_id" {
  value       = aws_api_gateway_rest_api.self_healing.id
  description = "REST API ID."
}
