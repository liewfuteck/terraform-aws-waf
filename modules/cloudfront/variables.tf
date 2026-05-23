variable "project_name"      { type = string }
variable "environment"        { type = string }
variable "s3_bucket_domain"   { type = string }
variable "s3_bucket_id"       { type = string }
variable "alb_dns_name"       { type = string }
variable "waf_web_acl_arn" {
  type    = string
  default = ""
}

variable "certificate_arn" {
  type    = string
  default = ""
}

variable "aliases" {
  type    = list(string)
  default = []
}
variable "origin_verify_secret" {
  description = "Secret header value sent from CloudFront to ALB to verify origin."
  type        = string
  sensitive   = true
}
