output "rule_group_namespace_arn" {
  description = "ARN of the AMP rule group namespace for edge device alerts"
  value       = aws_prometheus_rule_group_namespace.edge_devices.id
}
