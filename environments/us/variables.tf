variable "region_label" {
  description = "Short region identifier used in resource name prefixes (e.g. eu, us, ca, apac)"
  type        = string
  default     = "us"
}

variable "us_account_id" {
  type        = string
  description = "AWS account ID for the US regional account"
}

variable "central_vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "failover_vpc_cidr" {
  description = "CIDR of the DR central VPC (10.5.0.0/16) — allows DR API to query this regional DB"
  type        = string
  default     = "10.5.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use a single NAT Gateway instead of one per AZ"
  type        = bool
  default     = false
}

variable "flow_log_retention_days" {
  description = "VPC flow log retention in days"
  type        = number
  default     = 90
}

variable "central_alarm_sns_topic_arn" {
  description = "SNS topic ARN in the central account for alarm routing"
  type        = string
}

variable "aurora_cluster_identifier" {
  description = "Pre-existing Aurora cluster identifier in this regional account"
  type        = string
}

variable "aurora_db_endpoint" {
  description = "Aurora writer endpoint DNS name (for connectivity probe)"
  type        = string
}
