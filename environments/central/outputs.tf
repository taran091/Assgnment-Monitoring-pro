output "central_vpc_id" {
  value = module.central_vpc.vpc_id
}

output "peering_eu_id" {
  value = module.peering_eu.peering_connection_id
}

output "peering_us_id" {
  value = module.peering_us.peering_connection_id
}

output "peering_ca_id" {
  value = module.peering_ca.peering_connection_id
}

output "peering_apac_id" {
  value = module.peering_apac.peering_connection_id
}

output "alarm_sns_topic_arn" {
  value = aws_sns_topic.alarms.arn
}

output "grafana_endpoint" {
  description = "Grafana web UI — share with engineering teams"
  value       = module.observability.grafana_endpoint
}

output "amp_remote_write_endpoint" {
  description = "Configure this in the ECS API task as PROMETHEUS_REMOTE_WRITE_URL"
  value       = module.observability.amp_workspace_endpoint
}
