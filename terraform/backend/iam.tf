# ECS Execution Role
data "aws_iam_policy_document" "exec_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "ecs_exec_role" {
  name               = "${var.environment}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.exec_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECS Task Role (to allow s3:PutObject)
data "aws_iam_policy_document" "s3_put" {
  statement {
    effect = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.streams.arn}/*"
    ]
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.environment}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.exec_assume.json
}

resource "aws_iam_role_policy" "ecs_task_s3_put" {
  name   = "AllowS3PutObject"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.s3_put.json
}

# Lambda Execution Role
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec_role" {
  name               = "${var.environment}-lambda-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Basic Lambda logging
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# SQS permissions for Lambda
data "aws_iam_policy_document" "lambda_sqs" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [ aws_sqs_queue.yt_jobs.arn ]
  }
}

resource "aws_iam_role_policy" "lambda_sqs_policy" {
  name   = "LambdaSQSAccess"
  role   = aws_iam_role.lambda_exec_role.id
  policy = data.aws_iam_policy_document.lambda_sqs.json
}

# ECS RunTask permissions for Lambda
data "aws_iam_policy_document" "lambda_ecs" {
  statement {
    effect = "Allow"
    actions = [
      "ecs:RunTask",
      "iam:PassRole"
    ]
    resources = [
      aws_ecs_task_definition.recorder.arn,
      aws_iam_role.ecs_exec_role.arn,
      aws_iam_role.ecs_task_role.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda_ecs_policy" {
  name   = "LambdaECSAccess"
  role   = aws_iam_role.lambda_exec_role.id
  policy = data.aws_iam_policy_document.lambda_ecs.json
}

# --- Lambda needs PutItem & UpdateItem on the jobs table ---
data "aws_iam_policy_document" "lambda_ddb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
    resources = [ aws_dynamodb_table.jobs.arn ]
  }
}

resource "aws_iam_role_policy" "lambda_ddb_policy" {
  name   = "LambdaDDBAccess"
  role   = aws_iam_role.lambda_exec_role.id
  policy = data.aws_iam_policy_document.lambda_ddb.json
}

# --- ECS task needs UpdateItem on the jobs table ---
data "aws_iam_policy_document" "ecs_ddb" {
  statement {
    effect    = "Allow"
    actions   = ["dynamodb:UpdateItem"]
    resources = [ aws_dynamodb_table.jobs.arn ]
  }
}

resource "aws_iam_role_policy" "ecs_ddb_policy" {
  name   = "EcsTaskDDBAccess"
  role   = aws_iam_role.ecs_task_role.id
  policy = data.aws_iam_policy_document.ecs_ddb.json
}
