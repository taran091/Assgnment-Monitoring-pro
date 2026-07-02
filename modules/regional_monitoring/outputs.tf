output "probe_lambda_arn" {
  description = "ARN of the connectivity probe Lambda"
  value       = aws_lambda_function.probe.arn
}

output "db_reachable_alarm_arn" {
  description = "ARN of the connectivity alarm — subscribe to SNS for P1 alerting"
  value       = aws_cloudwatch_metric_alarm.db_reachable.arn
}

output "select_latency_alarm_arn" {
  description = "ARN of the SELECT latency alarm"
  value       = aws_cloudwatch_metric_alarm.select_latency.arn
}
