output "api_sg_id" {
  description = "ID of the central API security group (empty string if not created)"
  value       = length(aws_security_group.api) > 0 ? aws_security_group.api[0].id : ""
}

output "db_sg_id" {
  description = "ID of the regional database security group (empty string if not created)"
  value       = length(aws_security_group.db) > 0 ? aws_security_group.db[0].id : ""
}
