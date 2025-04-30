# Dead-letter queue
resource "aws_sqs_queue" "chronicle_jobs_dlq" {
  name                      = "${var.environment}-chronicle-jobs-dlq.fifo"
  fifo_queue                = true
  content_based_deduplication = true
}

# Main FIFO queue
resource "aws_sqs_queue" "chronicle_jobs" {
  name                       = "${var.environment}-chronicle-jobs.fifo"
  fifo_queue                 = true
  content_based_deduplication = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.chronicle_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}
