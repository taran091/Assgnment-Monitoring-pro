output "amp_workspace_id" {
  description = "Amazon Managed Prometheus workspace ID"
  value       = aws_prometheus_workspace.this.id
}

output "amp_workspace_endpoint" {
  description = "AMP remote_write endpoint — configure in ECS task sidecar or app config"
  value       = "${aws_prometheus_workspace.this.prometheus_endpoint}api/v1/remote_write"
}

output "amp_query_endpoint" {
  description = "AMP query endpoint — used as Grafana data source URL"
  value       = aws_prometheus_workspace.this.prometheus_endpoint
}

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = aws_grafana_workspace.this.id
}

output "grafana_endpoint" {
  description = "Grafana web UI URL — share with internal engineering teams"
  value       = "https://${aws_grafana_workspace.this.endpoint}"
}

output "grafana_role_arn" {
  description = "ARN of the Grafana IAM service role"
  value       = aws_iam_role.grafana.arn
}
