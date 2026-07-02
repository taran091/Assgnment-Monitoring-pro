variable "environment" {
  description = "Environment name (e.g., 'central', 'eu', 'us')"
  type        = string
}

variable "peering_connection_ids" {
  description = "Map of region name to VPC Peering Connection ID to monitor (central only)"
  type        = map(string)
  default     = {}
}

variable "alarm_sns_topic_arn" {
  description = "ARN of the SNS topic to send CloudWatch alarms to"
  type        = string
}

variable "api_function_name" {
  description = "Name of the Lambda/ECS service to monitor for errors (central only)"
  type        = string
  default     = ""
}

variable "latency_threshold_ms" {
  description = "API p95 latency threshold in milliseconds before alerting"
  type        = number
  default     = 2000
}

variable "error_rate_threshold_pct" {
  description = "API 5xx error rate percentage threshold before alerting"
  type        = number
  default     = 1
}

variable "tags" {
  description = "Additional tags to apply to monitoring resources"
  type        = map(string)
  default     = {}
}
