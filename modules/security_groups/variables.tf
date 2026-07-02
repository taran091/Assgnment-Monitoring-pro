variable "vpc_id" {
  description = "ID of the VPC in which to create security groups"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., 'central', 'eu', 'us')"
  type        = string
}

variable "regional_vpc_cidrs" {
  description = "List of CIDR blocks for all regional VPCs (used in central API SG ingress rules)"
  type        = list(string)
  default     = []
}

variable "central_vpc_cidr" {
  description = "CIDR block of the central API VPC (used in regional DB SG ingress rules)"
  type        = string
  default     = ""
}

variable "db_port" {
  description = "Port the regional database listens on (e.g., 5432 for PostgreSQL)"
  type        = number
  default     = 5432
}

variable "tags" {
  description = "Additional tags to apply to all security groups"
  type        = map(string)
  default     = {}
}

variable "failover_vpc_cidr" {
  description = "CIDR of the failover central VPC (10.5.0.0/16). When set, DB SG also allows ingress from this CIDR so the failover API can query the database during a regional failure."
  type        = string
  default     = ""
}
