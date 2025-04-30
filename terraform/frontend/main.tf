# 1. S3 bucket for static site
resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name

  acl = "private"

  tags = {
    Environment = var.environment
  }
}

# Prevent public ACLs
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for ${var.bucket_name}"
}

# 3. S3 bucket policy granting CloudFront read
data "aws_iam_policy_document" "s3_cf_policy" {
  statement {
    actions = ["s3:GetObject"]
    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.oai.iam_arn]
    }
    resources = ["${aws_s3_bucket.site.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "site_policy" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.s3_cf_policy.json
}

# 4. CloudFront distribution
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id   = "s3-${var.bucket_name}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-${var.bucket_name}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 60
    max_ttl                = 86400
  }

  # If you later add an API behavior for /api/*, you can override here.

  viewer_certificate {
    # use custom ACM if provided, otherwise default CloudFront cert
    dynamic "acm_certificate_arn" {
      for_each = var.acm_certificate_arn != "" ? [1] : []
      content {
        certificate         = var.acm_certificate_arn
        certificate_source  = "acm"
        ssl_support_method  = "sni-only"
      }
    }
    # fallback to default if no ACM cert
    cloudfront_default_certificate = var.acm_certificate_arn == ""
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = {
    Environment = var.environment
  }

  # Optional: log bucket, price class, etc.
}
