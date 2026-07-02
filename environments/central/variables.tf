# ── Core ──────────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region for the central account"
  type        = string
  default     = "eu-west-1"
}

variable "central_account_id" { type = string }
variable "central_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

# ── Workspace-replacement tunables ────────────────────────────────────────────
# In protex-observability these lived inside ws_config per workspace.
# Here they are plain variables — set them in terraform.tfvars.

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway (cost saving) instead of one per AZ"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "VPC flow log and AMP log retention in days"
  type        = number
  default     = 90
}

variable "latency_threshold_ms" {
  description = "API p99 latency CloudWatch alarm threshold (milliseconds)"
  type        = number
  default     = 2000
}

variable "error_rate_threshold_pct" {
  description = "API error rate CloudWatch alarm threshold (percent)"
  type        = number
  default     = 1
}

# ── Regional accounts ─────────────────────────────────────────────────────────

variable "eu_account_id" { type = string }
variable "eu_vpc_id" { type = string }
variable "eu_vpc_cidr" {
  type    = string
  default = "10.2.0.0/16"
}
variable "eu_private_route_table_ids" { type = list(string) }

variable "us_account_id" { type = string }
variable "us_vpc_id" { type = string }
variable "us_vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}
variable "us_private_route_table_ids" { type = list(string) }

variable "ca_account_id" { type = string }
variable "ca_vpc_id" { type = string }
variable "ca_vpc_cidr" {
  type    = string
  default = "10.3.0.0/16"
}
variable "ca_private_route_table_ids" { type = list(string) }

variable "apac_account_id" { type = string }
variable "apac_vpc_id" { type = string }
variable "apac_vpc_cidr" {
  type    = string
  default = "10.4.0.0/16"
}
variable "apac_private_route_table_ids" { type = list(string) }

# ── Grafana AMG ───────────────────────────────────────────────────────────────

variable "grafana_admin_group_ids" {
  description = "AWS SSO group IDs granted Grafana Admin access"
  type        = list(string)
  default     = []
}

# ── Aurora endpoints for Grafana PostgreSQL data sources ──────────────────────

variable "eu_aurora_endpoint"   { type = string; default = "" }
variable "eu_aurora_password"   { type = string; default = ""; sensitive = true }
variable "us_aurora_endpoint"   { type = string; default = "" }
variable "us_aurora_password"   { type = string; default = ""; sensitive = true }
variable "ca_aurora_endpoint"   { type = string; default = "" }
variable "ca_aurora_password"   { type = string; default = ""; sensitive = true }
variable "apac_aurora_endpoint" { type = string; default = "" }
variable "apac_aurora_password" { type = string; default = ""; sensitive = true }

# ── Route 53 failover ─────────────────────────────────────────────────────────

variable "internal_domain_name" {
  description = "Private hosted zone domain name"
  type        = string
  default     = "observability.protex.internal"
}

variable "primary_alb_dns_name" {
  description = "DNS name of the primary ALB (output from ECS/ALB module)"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Hosted zone ID of the primary ALB"
  type        = string
}

variable "failover_alb_dns_name" {
  description = "DNS name of the DR ALB in us-east-1 (from central-dr outputs)"
  type        = string
}

variable "failover_alb_zone_id" {
  description = "Hosted zone ID of the DR ALB"
  type        = string
}

variable "failover_vpc_id" {
  description = "VPC ID of the DR central VPC (from central-dr outputs)"
  type        = string
}
