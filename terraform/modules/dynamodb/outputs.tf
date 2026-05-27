output "table_name" {
  description = "Name of the incidents DynamoDB table"
  value       = aws_dynamodb_table.incidents.name
}

output "table_arn" {
  description = "ARN of the incidents DynamoDB table"
  value       = aws_dynamodb_table.incidents.arn
}
