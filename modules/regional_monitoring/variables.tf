variable "name_prefix" {
  description = "Resource name prefix (e.g. 'protex-prod-eu')"
  type        = string
}

variable "region" {
  description = "AWS region label for metric dimensions and tags (e.g. 'eu', 'us')"
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic ARN for all alarms"
  type        = string
}

# Aurora cluster — pre-existing, not managed by this module
variable "aurora_cluster_identifier" {
  description = "Aurora cluster identifier in this regional account"
  type        = string
}

variable "aurora_db_endpoint" {
  description = "Aurora cluster writer endpoint DNS name (used by connectivity probe)"
  type        = string
}

variable "aurora_db_port" {
  description = "Aurora port (default 5432 for PostgreSQL)"
  type        = number
  default     = 5432
}

variable "max_connections_threshold" {
  description = "Alarm when DatabaseConnections exceeds this value"
  type        = number
  default     = 800  # safe margin below Aurora PostgreSQL default max_connections
}

variable "select_latency_threshold_ms" {
  description = "Alarm when SelectLatency exceeds this value in milliseconds"
  type        = number
  default     = 200
}

variable "replica_lag_threshold_seconds" {
  description = "Alarm when AuroraReplicaLag exceeds this value in seconds"
  type        = number
  default     = 30
}

variable "probe_schedule" {
  description = "EventBridge schedule for connectivity probe (cron or rate)"
  type        = string
  default     = "rate(1 minute)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
