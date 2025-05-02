# Package the Lambda function
data "archive_file" "s3_torrent_creator" {
  type        = "zip"
  source_file = "${path.module}/lambda/s3_torrent_creator.py"
  output_path = "${path.module}/lambda/s3_torrent_creator.zip"
}

# Create a custom Lambda layer for transmission-cli tools
# Note: In a real implementation, you would need to create this layer manually
# and upload it to AWS since it requires native binaries
resource "aws_lambda_layer_version" "transmission_tools" {
  layer_name = "transmission-tools"
  description = "Lambda layer with transmission-cli tools for torrent creation"

  # This is a placeholder - in reality, this layer should be created externally
  # and referenced here by its ARN. The layer creation process would involve:
  # 1. Set up an Amazon Linux 2 environment
  # 2. Install transmission-cli
  # 3. Copy the binaries to the layer structure
  # 4. Zip and upload the layer
  filename = "${path.module}/lambda/transmission_tools_layer.zip"
  compatible_runtimes = ["python3.8", "python3.9"]
  
  # Only create this layer in a development environment
  # In production, reference an existing layer by ARN
  count = var.environment == "dev" ? 1 : 0
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash
    ]
  }
}

# IAM Role for S3 Torrent Lambda
resource "aws_iam_role" "s3_torrent_lambda_role" {
  name = "${var.environment}-s3-torrent-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

# Attach policy to the role
resource "aws_iam_role_policy" "s3_torrent_lambda_policy" {
  name = "${var.environment}-s3-torrent-lambda-policy"
  role = aws_iam_role.s3_torrent_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:HeadObject"
        ]
        Effect   = "Allow"
        Resource = [
          aws_s3_bucket.recordings.arn,
          "${aws_s3_bucket.recordings.arn}/*"
        ]
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:GetItem"
        ]
        Effect   = "Allow"
        Resource = aws_dynamodb_table.jobs.arn
      }
    ]
  })
}

# Lambda function
resource "aws_lambda_function" "s3_torrent_creator" {
  function_name    = "${var.environment}-s3-torrent-creator"
  filename         = data.archive_file.s3_torrent_creator.output_path
  source_code_hash = data.archive_file.s3_torrent_creator.output_base64sha256
  handler          = "s3_torrent_creator.lambda_handler"
  runtime          = "python3.9"
  role             = aws_iam_role.s3_torrent_lambda_role.arn
  timeout          = 300
  memory_size      = 1024

  # Attach the transmission tools layer if available (dev environment)
  layers = var.environment == "dev" ? [aws_lambda_layer_version.transmission_tools[0].arn] : []

  # In production, you would specify the ARN of a pre-created layer
  # layers = var.environment == "dev" ? [aws_lambda_layer_version.transmission_tools[0].arn] : ["arn:aws:lambda:${var.region}:${var.account_id}:layer:transmission-tools:1"]

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.recordings.id
      DDB_TABLE = aws_dynamodb_table.jobs.name
      TRACKERS  = "udp://opentracker.example.com:1337"
    }
  }

  # Provide a larger ephemeral storage for handling large files
  ephemeral_storage {
    size = 1024 # 1 GB
  }
}

# Create an empty placeholder zip file for the layer
resource "local_file" "placeholder_layer" {
  count = var.environment == "dev" ? 1 : 0
  filename = "${path.module}/lambda/transmission_tools_layer.zip"
  content  = "Placeholder for transmission tools layer"
}

# S3 bucket notification for the Lambda function
resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.recordings.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_torrent_creator.arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = "" # Optional: specify file extensions like .mp4
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# Lambda permission to allow S3 to invoke it
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_torrent_creator.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.recordings.arn
} 