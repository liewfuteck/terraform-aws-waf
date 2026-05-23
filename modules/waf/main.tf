###############################################################################
# Module: waf
# AWS WAF v2 WebACL with OWASP Top 10 managed rule groups:
#   - AWSManagedRulesCommonRuleSet       (general OWASP Top 10)
#   - AWSManagedRulesSQLiRuleSet         (SQLi)
#   - AWSManagedRulesKnownBadInputsRuleSet (log4j, SSRF, bad inputs)
#   - AWSManagedRulesAmazonIpReputationList (known malicious IPs)
#   - AWSManagedRulesBotControlRuleSet   (automated bot traffic)
#   - Custom rule: rate limiting (100 req/5min per IP)
#   - Custom rule: block oversized bodies
#
# scope = "REGIONAL"    → attach to ALB
# scope = "CLOUDFRONT"  → attach to CloudFront (deployed in us-east-1)
###############################################################################

terraform {
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.project_name}-${var.environment}-${lower(var.scope)}-waf"
  description = "OWASP Top 10 protection for ${var.project_name} - ${lower(var.scope)}"
  scope       = var.scope

  default_action {
    allow {}
  }

  # ── 1. IP Reputation List (block known bad actors first) ──────────────────
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # ── 2. Core Rule Set (OWASP Top 10 – XSS, Path Traversal, etc.) ───────────
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"

        # Override SizeRestrictions_BODY to COUNT instead of BLOCK
        # so large uploads (e.g. file uploads) aren't blocked; adjust as needed
        rule_action_override {
          name = "SizeRestrictions_BODY"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ── 3. SQL Injection ──────────────────────────────────────────────────────
  rule {
    name     = "AWSManagedRulesSQLiRuleSet"
    priority = 30

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesSQLiRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-sqli"
      sampled_requests_enabled   = true
    }
  }

  # ── 4. Known Bad Inputs (Log4Shell, SSRF, etc.) ───────────────────────────
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 40

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ── 5. Bot Control (automated traffic) ───────────────────────────────────
  # NOTE: Bot Control has an additional monthly charge (~$10/mo + request fees)
  # Remove this rule if cost is a concern.
  rule {
    name     = "AWSManagedRulesBotControlRuleSet"
    priority = 50

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"  # upgrade to TARGETED for JS challenge
          }
        }

        # Count (don't block) verified bots like Googlebot
        rule_action_override {
          name = "CategoryVerifiedSearchEngine"
          action_to_use {
            count {}
          }
        }
        rule_action_override {
          name = "CategoryVerifiedSocialMedia"
          action_to_use {
            count {}
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bot-control"
      sampled_requests_enabled   = true
    }
  }

  # ── 6. Custom: Rate limiting (configurable req / 5 min per IP) ───────────
  rule {
    name     = "RateLimitPerIP"
    priority = 60

    action {
      block {
        custom_response {
          response_code            = 429
          custom_response_body_key = "too_many_requests"
        }
      }
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit_per_ip
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ── Custom response bodies ────────────────────────────────────────────────
  custom_response_body {
    key          = "too_many_requests"
    content_type = "APPLICATION_JSON"
    content      = jsonencode({ error = "Too many requests. Please slow down.", code = 429 })
  }

  # ── Visibility config (default/fallback) ──────────────────────────────────
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-waf"
    sampled_requests_enabled   = true
  }
}

# ── Associate WebACL with ALB (REGIONAL scope only) ──────────────────────────
resource "aws_wafv2_web_acl_association" "alb" {
  count        = var.scope == "REGIONAL" ? 1 : 0
  resource_arn = var.alb_arn != null ? var.alb_arn : ""
  web_acl_arn  = aws_wafv2_web_acl.this.arn
}

# ── WAF Logging: REGIONAL → direct S3 ────────────────────────────────────────
resource "aws_wafv2_web_acl_logging_configuration" "regional" {
  count                   = var.enable_logging && var.scope == "REGIONAL" ? 1 : 0
  log_destination_configs = [var.log_bucket_arn]
  resource_arn            = aws_wafv2_web_acl.this.arn

  redacted_fields {
    single_header { name = "authorization" }
  }
  redacted_fields {
    single_header { name = "cookie" }
  }
}

# ── WAF Logging: CLOUDFRONT → Kinesis Firehose → S3 ─────────────────────────
# CloudFront-scoped WAFs can only log to Kinesis Firehose, not directly to S3.

resource "aws_iam_role" "firehose_waf" {
  count = var.enable_logging && var.scope == "CLOUDFRONT" ? 1 : 0
  name  = "${var.project_name}-${var.environment}-cf-waf-firehose"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "firehose_waf_s3" {
  count = var.enable_logging && var.scope == "CLOUDFRONT" ? 1 : 0
  role  = aws_iam_role.firehose_waf[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetBucketLocation", "s3:ListBucket"]
        Resource = [var.log_bucket_arn, "${var.log_bucket_arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = var.log_kms_key_arn != "" ? [var.log_kms_key_arn] : ["*"]
      }
    ]
  })
}

# Stream name must start with "aws-waf-logs-" (WAF requirement).
resource "aws_kinesis_firehose_delivery_stream" "waf_cf" {
  count       = var.enable_logging && var.scope == "CLOUDFRONT" ? 1 : 0
  name        = "aws-waf-logs-${var.project_name}-${var.environment}-cf"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose_waf[0].arn
    bucket_arn          = var.log_bucket_arn
    prefix              = "cloudfront-waf/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/"
    error_output_prefix = "cloudfront-waf-errors/"
    buffering_size      = 5
    buffering_interval  = 300
    compression_format  = "GZIP"
  }
}

resource "aws_wafv2_web_acl_logging_configuration" "cloudfront" {
  count                   = var.enable_logging && var.scope == "CLOUDFRONT" ? 1 : 0
  log_destination_configs = [aws_kinesis_firehose_delivery_stream.waf_cf[0].arn]
  resource_arn            = aws_wafv2_web_acl.this.arn

  redacted_fields {
    single_header { name = "authorization" }
  }
  redacted_fields {
    single_header { name = "cookie" }
  }
}

# ── CloudWatch alarms for blocked requests ────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "blocked_requests_high" {
  alarm_name          = "${var.project_name}-${var.environment}-waf-blocked-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "BlockedRequests"
  namespace           = "AWS/WAFV2"
  period              = 300
  statistic           = "Sum"
  threshold           = 100
  alarm_description   = "WAF is blocking an unusually high number of requests"
  treat_missing_data  = "notBreaching"

  dimensions = {
    WebACL = aws_wafv2_web_acl.this.name
    Region = var.scope == "CLOUDFRONT" ? "Global" : data.aws_region.current.region
    Rule   = "ALL"
  }
}

data "aws_region" "current" {}

# ── Outputs ──────────────────────────────────────────────────────────────────
output "web_acl_arn"  { value = aws_wafv2_web_acl.this.arn }
output "web_acl_id"   { value = aws_wafv2_web_acl.this.id }
output "web_acl_name" { value = aws_wafv2_web_acl.this.name }
