variable "table_name" {
  description = "DynamoDB table name for incidents"
  type        = string
  default     = "self-healing-incidents"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
}
