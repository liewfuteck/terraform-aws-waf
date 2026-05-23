###############################################################################
# Root – orchestrates all modules
# Architecture: S3 (static) → CloudFront → ALB → EC2 origin
#               AWS WAF v2 attached to both CloudFront and ALB
#               CloudTrail + WAF logging
###############################################################################

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Uncomment and fill in to use remote state (recommended for production).
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "castlery/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

# Primary region for most resources
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# WAF for CloudFront MUST be created in us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

# ── VPC ───────────────────────────────────────────────────────────────────────
module "vpc" {
  source               = "./modules/vpc"
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

# ── S3 (static assets / origin bucket) ───────────────────────────────────────
module "s3" {
  source       = "./modules/s3"
  project_name = var.project_name
  environment  = var.environment
}

# ── ALB (application load balancer + EC2 target) ─────────────────────────────
module "alb" {
  source               = "./modules/alb"
  project_name         = var.project_name
  environment          = var.environment
  vpc_id               = module.vpc.vpc_id
  public_subnet_ids    = module.vpc.public_subnet_ids
  certificate_arn      = var.certificate_arn   # set "" to skip HTTPS listener
  origin_verify_secret = var.origin_verify_secret
}

# ── WAF – regional (attached to ALB) ────────────────────────────────────────
module "waf_regional" {
  source            = "./modules/waf"
  project_name      = var.project_name
  environment       = var.environment
  scope             = "REGIONAL"
  alb_arn           = module.alb.alb_arn
  enable_logging    = var.enable_logging
  log_bucket_arn    = var.enable_logging ? module.logging[0].waf_log_bucket_arn : ""
  log_kms_key_arn   = var.enable_logging ? module.logging[0].kms_key_arn : ""
  rate_limit_per_ip = var.waf_rate_limit
}

# ── WAF – CloudFront (must be us-east-1) ────────────────────────────────────
module "waf_cloudfront" {
  source            = "./modules/waf"
  project_name      = var.project_name
  environment       = var.environment
  scope             = "CLOUDFRONT"
  alb_arn           = null
  enable_logging    = var.enable_logging
  log_bucket_arn    = var.enable_logging ? module.logging[0].waf_log_bucket_arn : ""
  log_kms_key_arn   = var.enable_logging ? module.logging[0].kms_key_arn : ""
  rate_limit_per_ip = var.waf_rate_limit

  providers = {
    aws = aws.us_east_1
  }
}

# ── CloudFront ───────────────────────────────────────────────────────────────
module "cloudfront" {
  source               = "./modules/cloudfront"
  project_name         = var.project_name
  environment          = var.environment
  s3_bucket_domain     = module.s3.bucket_regional_domain
  s3_bucket_id         = module.s3.bucket_id
  alb_dns_name         = module.alb.alb_dns_name
  waf_web_acl_arn      = module.waf_cloudfront.web_acl_arn
  certificate_arn      = var.cloudfront_certificate_arn
  aliases              = var.cloudfront_aliases
  origin_verify_secret = var.origin_verify_secret
}

# ── Logging (CloudTrail + WAF log bucket) ────────────────────────────────────
module "logging" {
  count        = var.enable_logging ? 1 : 0
  source       = "./modules/logging"
  project_name = var.project_name
  environment  = var.environment
  aws_account_id = data.aws_caller_identity.current.account_id
  aws_region     = var.aws_region
}

data "aws_caller_identity" "current" {}
