variable "name_prefix" {
  description = "Resource name prefix (e.g. 'protex-prod')"
  type        = string
}

variable "internal_domain_name" {
  description = "Private hosted zone domain (e.g. 'observability.protex.internal')"
  type        = string
  default     = "observability.protex.internal"
}

variable "health_check_path" {
  description = "HTTPS path the health check polls on the primary ALB"
  type        = string
  default     = "/health"
}

variable "health_check_interval" {
  description = "Seconds between health check requests (10 or 30)"
  type        = number
  default     = 10
}

variable "health_check_failure_threshold" {
  description = "Consecutive failures before Route 53 marks the endpoint unhealthy"
  type        = number
  default     = 3
}

# Primary (us-east-1)
variable "primary_alb_dns_name" {
  description = "DNS name of the primary ALB (us-east-1)"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "Hosted zone ID of the primary ALB"
  type        = string
}

variable "primary_vpc_id" {
  description = "VPC ID of the primary central VPC (to associate with private hosted zone)"
  type        = string
}

# Failover (eu-west-1)
variable "failover_alb_dns_name" {
  description = "DNS name of the failover ALB (eu-west-1)"
  type        = string
}

variable "failover_alb_zone_id" {
  description = "Hosted zone ID of the failover ALB"
  type        = string
}

variable "failover_vpc_id" {
  description = "VPC ID of the failover central VPC (associated with the same private hosted zone)"
  type        = string
}

variable "failover_region" {
  description = "AWS region of the failover environment"
  type        = string
  default     = "eu-west-1"
}

variable "tags" {
  type    = map(string)
  default = {}
}
