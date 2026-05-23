###############################################################################
# Outputs – root module
###############################################################################

output "cloudfront_domain" {
  description = "CloudFront distribution domain (access your site here)."
  value       = module.cloudfront.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (needed for cache invalidations)."
  value       = module.cloudfront.distribution_id
}

output "alb_dns_name" {
  description = "ALB DNS name (internal – traffic should flow via CloudFront)."
  value       = module.alb.alb_dns_name
}

output "s3_bucket_name" {
  description = "S3 bucket holding static assets."
  value       = module.s3.bucket_id
}

output "waf_regional_web_acl_arn" {
  description = "WAF WebACL ARN attached to the ALB."
  value       = module.waf_regional.web_acl_arn
}

output "waf_cloudfront_web_acl_arn" {
  description = "WAF WebACL ARN attached to CloudFront."
  value       = module.waf_cloudfront.web_acl_arn
}

output "cloudtrail_arn" {
  description = "CloudTrail trail ARN (empty when logging disabled)."
  value       = var.enable_logging ? module.logging[0].cloudtrail_arn : "logging disabled"
}
