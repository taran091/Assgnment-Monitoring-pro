output "peering_event_rule_arns" {
  description = "ARNs of EventBridge rules monitoring peering connection state changes"
  value       = { for k, v in aws_cloudwatch_event_rule.peering_state_change : k => v.arn }
}

output "api_latency_alarm_arn" {
  description = "ARN of the p95 latency CloudWatch alarm"
  value       = length(aws_cloudwatch_metric_alarm.api_latency_p95) > 0 ? aws_cloudwatch_metric_alarm.api_latency_p95[0].arn : ""
}

output "dashboard_name" {
  description = "Name of the CloudWatch dashboard (central only)"
  value       = length(aws_cloudwatch_dashboard.protex_network) > 0 ? aws_cloudwatch_dashboard.protex_network[0].dashboard_name : ""
}
