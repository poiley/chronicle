# DynamoDB table for job tracking
resource "aws_dynamodb_table" "jobs" {
  name         = "${var.environment}-jobs"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "jobId"

  attribute {
    name = "jobId"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  tags = {
    Name        = "${var.environment}-jobs"
    Environment = var.environment
  }
} 