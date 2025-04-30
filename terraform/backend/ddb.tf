resource "aws_dynamodb_table" "jobs" {
  name         = "${var.environment}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "jobId"

  attribute {
    name = "jobId"
    type = "S"
  }

  # Enable TTL on the numeric "ttl" attribute (epoch seconds)
  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Environment = var.environment
  }
}

output "ddb_table_name" {
  description = "DynamoDB jobs table"
  value       = aws_dynamodb_table.jobs.name
}
