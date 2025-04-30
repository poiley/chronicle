output "site_bucket" {
  description = "S3 bucket for the web site"
  value       = aws_s3_bucket.site.id
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.site.domain_name
}
