variable "vpc_name" {
  description = "Name tag for the VPC and related resources"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must not overlap with any peered VPC."
  type        = string
}

variable "azs" {
  description = "List of availability zones to deploy subnets into (minimum 2 for HA)"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets (one per AZ)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private (app-tier) subnets (one per AZ)"
  type        = list(string)
}

variable "data_subnet_cidrs" {
  description = "CIDR blocks for data (database-tier) subnets (one per AZ)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "Whether to provision NAT Gateways for private subnet egress"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway instead of one per AZ (reduces cost but lowers HA)"
  type        = bool
  default     = false
}

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs to CloudWatch for network auditing"
  type        = bool
  default     = true
}

variable "flow_log_retention_days" {
  description = "Retention period in days for VPC Flow Log CloudWatch log group"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
