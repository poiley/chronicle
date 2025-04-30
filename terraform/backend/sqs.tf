# Dead-letter queue
resource "aws_sqs_queue" "yt_jobs_dlq" {
  name                      = "${var.environment}-yt-jobs-dlq.fifo"
  fifo_queue                = true
  content_based_deduplication = true
}

# Main FIFO queue
resource "aws_sqs_queue" "yt_jobs" {
  name                       = "${var.environment}-yt-jobs.fifo"
  fifo_queue                 = true
  content_based_deduplication = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.yt_jobs_dlq.arn
    maxReceiveCount     = 3
  })
}
