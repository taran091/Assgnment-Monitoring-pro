output "hosted_zone_id" {
  description = "ID of the private Route 53 hosted zone"
  value       = aws_route53_zone.internal.zone_id
}

output "api_hostname" {
  description = "Internal API hostname — use this in all client configuration"
  value       = "api.${var.internal_domain_name}"
}

output "primary_health_check_id" {
  description = "Route 53 health check ID for the primary ALB"
  value       = aws_route53_health_check.primary.id
}

output "health_alarm_arn" {
  description = "CloudWatch alarm ARN — subscribe to SNS to alert on primary failure"
  value       = aws_cloudwatch_metric_alarm.primary_health.arn
}
