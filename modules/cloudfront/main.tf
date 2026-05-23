###############################################################################
# Module: cloudfront
# CloudFront distribution with:
#   - S3 origin (OAC) for static assets  (/*.html, /assets/*)
#   - ALB origin for dynamic API traffic (/api/*)
#   - WAF WebACL attached
#   - HTTPS redirect, TLS 1.2 minimum
###############################################################################

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

# ── Origin Access Control (replaces deprecated OAI) ─────────────────────────
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.project_name}-${var.environment}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── S3 bucket policy – allow only CloudFront OAC ────────────────────────────
data "aws_iam_policy_document" "s3_cf_policy" {
  statement {
    sid     = "AllowCloudFrontOAC"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${var.s3_bucket_id}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cf_access" {
  bucket = var.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_cf_policy.json
}

# ── CloudFront distribution ──────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${var.project_name}-${var.environment}"
  default_root_object = "index.html"
  web_acl_id          = var.waf_web_acl_arn != "" ? var.waf_web_acl_arn : null
  aliases             = length(var.aliases) > 0 ? var.aliases : null
  price_class         = "PriceClass_All"

  # ── Origin 1: S3 static assets ──────────────────────────────────────────
  origin {
    domain_name              = var.s3_bucket_domain
    origin_id                = "S3Origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ── Origin 2: ALB dynamic API ────────────────────────────────────────────
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "ALBOrigin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]

      # Connection settings
      origin_read_timeout      = 30
      origin_keepalive_timeout = 5
    }

    # Custom header so ALB can verify requests come from CloudFront
    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_verify_secret
    }
  }

  # ── Default cache behaviour → S3 ─────────────────────────────────────────
  default_cache_behavior {
    target_origin_id       = "S3Origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400   # 1 day
    max_ttl     = 31536000 # 1 year
  }

  # ── /api/* → ALB (no caching) ─────────────────────────────────────────────
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "ALBOrigin"
    viewer_protocol_policy = "https-only"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = true
      headers      = ["Authorization", "Accept", "Content-Type", "X-Requested-With"]
      cookies { forward = "all" }
    }

    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0
  }

  # ── TLS ──────────────────────────────────────────────────────────────────
  viewer_certificate {
    acm_certificate_arn      = var.certificate_arn != "" ? var.certificate_arn : null
    cloudfront_default_certificate = var.certificate_arn == "" ? true : false
    minimum_protocol_version = var.certificate_arn != "" ? "TLSv1.2_2021" : "TLSv1"
    ssl_support_method       = var.certificate_arn != "" ? "sni-only" : null
  }

  # ── Geo restriction (open by default) ────────────────────────────────────
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # ── Standard logging ─────────────────────────────────────────────────────
  # Uncomment and set a logging bucket to capture CF access logs
  # logging_config {
  #   bucket          = "${var.log_bucket}.s3.amazonaws.com"
  #   include_cookies = false
  #   prefix          = "cloudfront/"
  # }
}

# ── Outputs ──────────────────────────────────────────────────────────────────
output "domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}
