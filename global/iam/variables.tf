variable "central_account_id" {
  description = "AWS account ID of the central (hub) account"
  type        = string
}

variable "external_id" {
  description = "STS ExternalId condition — prevents confused-deputy attacks on cross-account role assumptions"
  type        = string
  sensitive   = true
}

variable "regional_db_arn" {
  description = "ARN of the Aurora cluster in this regional account"
  type        = string
}

variable "regional_db_secret_arn" {
  description = "ARN of the Secrets Manager secret holding DB credentials"
  type        = string
}
