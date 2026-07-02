output "dr_vpc_id" {
  description = "Pass to environments/central terraform.tfvars as failover_vpc_id"
  value       = module.dr_vpc.vpc_id
}

output "dr_vpc_cidr" {
  value = "10.5.0.0/16"
}

output "dr_private_route_table_ids" {
  value = module.dr_vpc.private_route_table_ids
}
