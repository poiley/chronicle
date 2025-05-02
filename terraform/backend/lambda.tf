# Package the Lambda dispatcher
data "archive_file" "lambda_dispatch" {
  type        = "zip"
  source_file = "${path.module}/lambda/dispatch_to_ecs.py"
  output_path = "${path.module}/lambda/dispatch_to_ecs.zip"
}

# Lambda function
resource "aws_lambda_function" "dispatch" {
  function_name    = "${var.environment}-dispatch-to-ecs"
  filename         = data.archive_file.lambda_dispatch.output_path
  source_code_hash = data.archive_file.lambda_dispatch.output_base64sha256
  handler          = "dispatch_to_ecs.lambda_handler"
  runtime          = "python3.9"
  role             = aws_iam_role.lambda_exec_role.arn
  timeout          = 300

  environment {
    variables = {
      # ECS & S3 settings
      ECS_CLUSTER        = aws_ecs_cluster.this.name
      ECS_TASK_DEF       = aws_ecs_task_definition.recorder.arn
      TRANSMISSION_TASK_DEF = aws_ecs_task_definition.transmission.arn
      S3_BUCKET          = aws_s3_bucket.streams.bucket
      CONTAINER_NAME     = var.container_name
      DDB_TABLE          = aws_dynamodb_table.jobs.name

      # VPC networking for Fargate
      SUBNET_IDS         = join(",", aws_public_subnet.public[*].id)
      SECURITY_GROUP_IDS = aws_security_group.ecs_tasks.id
    }
  }
}

# Event source mapping from FIFO SQS → this Lambda
resource "aws_lambda_event_source_mapping" "sqs_dispatch" {
  event_source_arn = aws_sqs_queue.chronicle_jobs.arn
  function_name    = aws_lambda_function.dispatch.arn
  batch_size       = 1
  enabled          = true
}
