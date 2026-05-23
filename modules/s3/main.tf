###############################################################################
# Module: s3
# Creates a private S3 bucket for static assets served via CloudFront OAC.
###############################################################################

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

resource "aws_s3_bucket" "this" {
  bucket = "${var.project_name}-${var.environment}-static-${random_id.suffix.hex}"

  # Prevent accidental deletion of bucket with content
  lifecycle {
    prevent_destroy = false  # set true in production
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# Block ALL public access – CloudFront uses OAC (Origin Access Control)
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning for content rollbacks
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Server-side encryption at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Upload a minimal index.html so the site works immediately after deploy
resource "aws_s3_object" "index" {
  bucket       = aws_s3_bucket.this.id
  key          = "index.html"
  content_type = "text/html"
  content      = <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <title>${var.project_name}</title>
      <style>
        body { font-family: sans-serif; display: flex; align-items: center;
               justify-content: center; height: 100vh; margin: 0;
               background: #0f172a; color: #e2e8f0; }
        h1   { font-size: 2rem; }
        p    { color: #94a3b8; }
      </style>
    </head>
    <body>
      <div style="text-align:center">
        <h1>&#128274; ${var.project_name}</h1>
        <p>Secured with AWS WAF &middot; CloudFront &middot; ALB</p>
      </div>
    </body>
    </html>
  HTML
}

# ── Outputs ──────────────────────────────────────────────────────────────────
output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_regional_domain" {
  value = aws_s3_bucket.this.bucket_regional_domain_name
}

output "bucket_arn" {
  value = aws_s3_bucket.this.arn
}
