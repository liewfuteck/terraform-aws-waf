# AWS Secure Web App – Terraform

> **Cloud-hosted web environment on AWS with WAF configured for OWASP Top 10 detection/blocking, including SQLi, XSS, and automated bot traffic.**

## Architecture

```
Internet
   │
   ▼
AWS WAF (CloudFront scope)        ← OWASP rules, rate-limit, bot control
   │
   ▼
CloudFront (CDN + TLS termination)
   ├── /api/*  ──────────────────► ALB
   │                                │
   │                            AWS WAF (Regional scope)
   │                                │
   │                            EC2 / ECS / Lambda
   │
   └── /* (default) ─────────────► S3 (static assets, via OAC)
```

### Components

| Resource | Purpose |
|---|---|
| **S3** | Private bucket for static HTML/CSS/JS; served via CloudFront OAC (no public access) |
| **CloudFront** | CDN, TLS 1.2+, HTTP→HTTPS redirect, two origins (S3 + ALB) |
| **ALB** | Application Load Balancer; HTTPS listener with origin-verify header check |
| **WAF (CloudFront)** | Protects the CDN edge — blocks before traffic reaches your origin |
| **WAF (Regional/ALB)** | Second layer at the ALB; catches anything that bypasses CloudFront |
| **CloudTrail** | Multi-region audit trail; management + S3 data events; logs to S3 + CloudWatch Logs |
| **KMS** | Encryption key for all log buckets |

---

## WAF Rules

Both WebACLs (CloudFront + ALB) contain identical rule sets:

| Priority | Rule | Threat |
|---|---|---|
| 10 | `AWSManagedRulesAmazonIpReputationList` | Known malicious IPs, botnets |
| 20 | `AWSManagedRulesCommonRuleSet` | OWASP Top 10: XSS, path traversal, bad headers |
| 30 | `AWSManagedRulesSQLiRuleSet` | SQL injection |
| 40 | `AWSManagedRulesKnownBadInputsRuleSet` | Log4Shell, SSRF, malformed input |
| 50 | `AWSManagedRulesBotControlRuleSet` | Automated scrapers, credential stuffing |
| 60 | `RateLimitPerIP` *(custom)* | 100 req / 5 min per source IP → HTTP 429 |

> **Cost note:** Bot Control costs ~$10/month + $1/million requests on top of standard WAF pricing. Remove rule priority 50 if cost is a concern.

---

## Prerequisites

- Terraform ≥ 1.6
- AWS CLI configured (`aws configure`)
- An existing VPC with at least two public subnets
- (Optional) ACM certificates for custom domains

## Quick Start

```bash
# 1. Clone / copy project
cd terraform-aws-waf

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars – at minimum set vpc_id and public_subnet_ids

# 3. Initialise
terraform init

# 4. Preview changes
terraform plan

# 5. Deploy (~5–10 minutes; CloudFront takes longest)
terraform apply

# 6. Get your CloudFront URL
terraform output cloudfront_domain
```

## Deploying static content

```bash
# After apply, push your static files to S3
aws s3 sync ./dist/ s3://$(terraform output -raw s3_bucket_name)/ --delete

# Invalidate the CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id $(terraform output -raw cloudfront_distribution_id) \
  --paths "/*"
```

## Enabling HTTPS (recommended)

1. **Request an ACM certificate** in the same region as your ALB (e.g. `ap-southeast-1`) for the ALB.
2. **Request a second ACM certificate** in `us-east-1` for CloudFront.
3. Add both ARNs and your domain aliases to `terraform.tfvars`:

```hcl
certificate_arn            = "arn:aws:acm:ap-southeast-1:ACCOUNT:certificate/..."
cloudfront_certificate_arn = "arn:aws:acm:us-east-1:ACCOUNT:certificate/..."
cloudfront_aliases         = ["www.example.com"]
```

## Viewing logs

**WAF logs** – stored in `aws-waf-logs-<project>-<env>` S3 bucket. Query with Athena:

```sql
-- Athena table DDL is auto-generated when you enable WAF logging in the console,
-- or create it manually pointing at the S3 prefix.
SELECT timestamp, action, httprequest.clientip, httprequest.uri
FROM waf_logs
WHERE action = 'BLOCK'
ORDER BY timestamp DESC
LIMIT 100;
```

**CloudTrail** – logs land in `<project>-<env>-cloudtrail-logs` and stream to the
`/aws/cloudtrail/<project>-<env>` CloudWatch Logs group for real-time alerting.

## Security hardening checklist

- [ ] Change `origin_verify_secret` to a random 32-char string and store in AWS Secrets Manager
- [ ] Set `enable_deletion_protection = true` on the ALB in production
- [ ] Narrow CloudTrail `data_resource` from all S3 to your specific bucket ARN
- [ ] Add ALB access logs to an S3 bucket for full request visibility
- [ ] Enable CloudFront access logging
- [ ] Set up SNS notifications on the CloudWatch WAF alarm
- [ ] Consider AWS Shield Advanced for DDoS protection on critical workloads

## Tear down

```bash
terraform destroy
```

> If `prevent_destroy = true` is set on the S3 bucket, empty it first:
> `aws s3 rm s3://<bucket-name> --recursive`

---

## File structure

```
terraform-aws-waf/
├── main.tf                   # Root orchestration
├── variables.tf              # Input variables
├── outputs.tf                # Key outputs (CloudFront URL, WAF ARNs, etc.)
├── terraform.tfvars.example  # Template – copy to terraform.tfvars
└── modules/
    ├── s3/         main.tf, variables.tf
    ├── cloudfront/ main.tf, variables.tf
    ├── alb/        main.tf, variables.tf
    ├── waf/        main.tf, variables.tf   ← reused for both scopes
    └── logging/    main.tf, variables.tf
```


## Security best practices

```
AWS secrets (access keys) kept in AWS configuration file and never pushed online (Git repository)
```