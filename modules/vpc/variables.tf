variable "project_name" { type = string }
variable "environment"   { type = string }

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy into. Length must match public and private subnet CIDR lists."
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ). Hosts the ALB."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets (one per AZ). Hosts EC2/ECS/Lambda."
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.20.0/24"]
}
