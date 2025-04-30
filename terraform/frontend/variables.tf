variable "aws_region" {
  description = "AWS region for S3 bucket (e.g. us-west-2)"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Deployment environment (used for naming)"
  type        = string
  default     = "prod"
}

variable "bucket_name" {
  description = "Name for the S3 bucket to host the site"
  type        = string
  default     = "yt-grabber-web-${var.environment}"
}

variable "acm_certificate_arn" {
  description = <<-EOF
    Optional ACM certificate ARN in us-east-1 for a custom domain.
    If empty, CloudFront's default certificate (*.cloudfront.net) is used.
  EOF
  type    = string
  default = ""
}
