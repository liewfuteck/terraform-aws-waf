###############################################################################
# Input variables – root module
###############################################################################

variable "project_name" {
  description = "Short name used to prefix all resource names."
  type        = string
  default     = "secure-webapp"
}

variable "environment" {
  description = "Deployment environment (prod, staging, dev)."
  type        = string
  default     = "prod"
}

variable "aws_region" {
  description = "Primary AWS region for ALB, WAF regional, S3, etc."
  type        = string
  default     = "ap-southeast-1"  # Singapore
}

# ── Networking ───────────────────────────────────────────────────────────────
variable "vpc_cidr" {
  description = "CIDR block for the VPC created by this project."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into. Defaults to two AZs in ap-southeast-1."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (ALB). One per AZ."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (EC2/ECS/Lambda). One per AZ."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}

# ── TLS certificates ─────────────────────────────────────────────────────────
variable "certificate_arn" {
  description = "ACM certificate ARN for the ALB HTTPS listener (regional). Leave empty to use HTTP only."
  type        = string
  default     = ""
}

variable "cloudfront_certificate_arn" {
  description = "ACM certificate ARN for CloudFront (must be in us-east-1). Leave empty for default CloudFront cert."
  type        = string
  default     = ""
}

variable "cloudfront_aliases" {
  description = "Custom domain aliases for CloudFront (e.g. [\"www.example.com\"]). Leave empty to use default *.cloudfront.net domain."
  type        = list(string)
  default     = []
}

# ── Feature flags ────────────────────────────────────────────────────────────
variable "enable_logging" {
  description = "Set to true to enable CloudTrail + WAF logging."
  type        = bool
  default     = true
}

# ── WAF tuning ────────────────────────────────────────────────────────────────
variable "waf_rate_limit" {
  description = "Max requests per 5-minute window per source IP before WAF returns HTTP 429."
  type        = number
  default     = 2000
}

# ── Security ──────────────────────────────────────────────────────────────────
variable "origin_verify_secret" {
  description = "Secret value sent as X-Origin-Verify header from CloudFront to ALB. Must be a random string; store the value in AWS Secrets Manager."
  type        = string
  sensitive   = true
}
