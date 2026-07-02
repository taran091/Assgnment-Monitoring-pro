variable "name_prefix" {
  description = "Resource name prefix (e.g. 'protex-prod')"
  type        = string
}

variable "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID — edge devices remote_write here"
  type        = string
}

variable "alarm_sns_topic_arn" {
  description = "SNS topic for device offline and performance alerts"
  type        = string
}

variable "device_offline_threshold_minutes" {
  description = "Alert if a device heartbeat is missing for this many minutes"
  type        = number
  default     = 5
}

variable "cpu_threshold_pct" {
  description = "Alert if device CPU exceeds this percentage for 5 minutes (AI inference load)"
  type        = number
  default     = 90
}

variable "disk_free_threshold_gb" {
  description = "Alert if video buffer disk has less than this many GB free"
  type        = number
  default     = 10
}

variable "inference_error_threshold" {
  description = "Alert if AI inference error rate exceeds this per minute"
  type        = number
  default     = 5
}

variable "tags" {
  type    = map(string)
  default = {}
}
