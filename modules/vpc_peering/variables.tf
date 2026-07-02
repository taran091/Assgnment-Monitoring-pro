variable "peering_name" {
  description = "Descriptive name for this peering connection (e.g., 'central-to-eu')"
  type        = string
}

# ── Requester side (always the Central API account) ───────────────────────────

variable "requester_vpc_id" {
  description = "VPC ID of the requester (central API VPC)"
  type        = string
}

variable "requester_route_table_ids" {
  description = "Route table IDs in the requester VPC that need routes to the accepter CIDR"
  type        = list(string)
}

variable "requester_region" {
  description = "AWS region of the requester VPC"
  type        = string
}

variable "requester_account_id" {
  description = "AWS account ID of the requester"
  type        = string
}

# ── Accepter side (regional account) ─────────────────────────────────────────

variable "accepter_vpc_id" {
  description = "VPC ID of the accepter (regional VPC)"
  type        = string
}

variable "accepter_vpc_cidr" {
  description = "CIDR block of the accepter VPC (added as a route in the requester)"
  type        = string
}

variable "accepter_route_table_ids" {
  description = "Route table IDs in the accepter VPC that need a return route to the requester CIDR"
  type        = list(string)
}

variable "accepter_region" {
  description = "AWS region of the accepter VPC"
  type        = string
}

variable "accepter_account_id" {
  description = "AWS account ID of the accepter"
  type        = string
}

variable "requester_vpc_cidr" {
  description = "CIDR block of the requester VPC (added as a return route in the accepter)"
  type        = string
}

variable "tags" {
  description = "Additional tags to apply to peering resources"
  type        = map(string)
  default     = {}
}
