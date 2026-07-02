variable "name_prefix" {
  description = "Prefix applied to all resource names (e.g. 'protex-prod')"
  type        = string
}

variable "grafana_auth_providers" {
  description = "Authentication providers for Grafana. AWS_SSO recommended for internal teams."
  type        = list(string)
  default     = ["AWS_SSO"]
}

variable "amp_log_retention_days" {
  description = "Retention for AMP audit logs in CloudWatch"
  type        = number
  default     = 30
}

variable "alert_sns_topic_arn" {
  description = "SNS topic ARN where Grafana alert notifications are forwarded"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "grafana_subnet_ids" {
  description = "Subnet IDs for AMG VPC configuration (private subnets in central VPC)"
  type        = list(string)
  default     = []
}

variable "grafana_security_group_ids" {
  description = "Security group IDs for AMG VPC configuration"
  type        = list(string)
  default     = []
}

variable "eu_aurora_endpoint"   { type = string; default = "" }
variable "eu_aurora_password"   { type = string; default = ""; sensitive = true }
variable "us_aurora_endpoint"   { type = string; default = "" }
variable "us_aurora_password"   { type = string; default = ""; sensitive = true }
variable "ca_aurora_endpoint"   { type = string; default = "" }
variable "ca_aurora_password"   { type = string; default = ""; sensitive = true }
variable "apac_aurora_endpoint" { type = string; default = "" }
variable "apac_aurora_password" { type = string; default = ""; sensitive = true }
