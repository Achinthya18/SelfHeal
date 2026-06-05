variable "environment" {
  type        = string
  description = "Deployment environment (dev, prod)."
}

variable "step_functions_arn" {
  type        = string
  description = "ARN of the self-healing Step Functions state machine."
}
