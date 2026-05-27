resource "aws_dynamodb_table" "incidents" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "incident_id"
  range_key    = "created_at"

  attribute {
    name = "incident_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }
}
