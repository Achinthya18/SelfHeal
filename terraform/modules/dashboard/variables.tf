variable "environment" {
  type        = string
  description = "Deployment environment suffix (e.g. dev, prod)."
}

variable "aws_region" {
  type        = string
  description = "AWS region the dashboard lives in (must match the resources being charted)."
}

variable "state_machine_arn" {
  type        = string
  description = "ARN of the Step Functions state machine to chart (used as StateMachineArn dimension)."
}

variable "lambda_function_names" {
  type = object({
    diagnostic          = string
    send_approval_email = string
    approval_callback   = string
    execute_runbook     = string
    send_result_email   = string
  })
  description = "Function names of all five pipeline Lambdas."
}

variable "dynamodb_table_name" {
  type        = string
  description = "Incidents table name."
}

variable "api_gateway_name" {
  type        = string
  description = "REST API name of the approval API (used as the ApiName dimension on AWS/ApiGateway metrics)."
}

variable "api_gateway_stage" {
  type        = string
  description = "API Gateway stage name (e.g. v1)."
  default     = "v1"
}

variable "alarm_names" {
  type        = list(string)
  description = "Self-healing pipeline alarm names to surface on the dashboard."
}
