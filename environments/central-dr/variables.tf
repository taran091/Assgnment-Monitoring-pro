variable "central_account_id" { type = string }

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
