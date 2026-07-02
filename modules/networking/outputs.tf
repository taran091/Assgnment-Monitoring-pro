output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "The CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of all public subnets"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "IDs of all private (app-tier) subnets"
  value       = aws_subnet.private[*].id
}

output "data_subnet_ids" {
  description = "IDs of all data (database-tier) subnets"
  value       = aws_subnet.data[*].id
}

output "private_route_table_ids" {
  description = "IDs of the per-AZ private route tables (used to add VPC peering routes)"
  value       = aws_route_table.private[*].id
}

output "public_route_table_id" {
  description = "ID of the shared public route table"
  value       = aws_route_table.public.id
}
