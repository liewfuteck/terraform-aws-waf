variable "project_name" { type = string }
variable "environment"   { type = string }

variable "scope" {
  type        = string
  description = "REGIONAL (ALB) or CLOUDFRONT"
  validation {
    condition     = contains(["REGIONAL", "CLOUDFRONT"], var.scope)
    error_message = "scope must be REGIONAL or CLOUDFRONT"
  }
}

variable "alb_arn" {
  type    = string
  default = null
}

variable "enable_logging" {
  type    = bool
  default = false
}

variable "log_bucket_arn" {
  type    = string
  default = ""
}

variable "log_kms_key_arn" {
  description = "ARN of the KMS key used to encrypt the WAF log bucket. Required when enable_logging is true."
  type        = string
  default     = ""
}

variable "rate_limit_per_ip" {
  description = "Max requests per 5-minute window per source IP before returning HTTP 429."
  type        = number
  default     = 2000
}
