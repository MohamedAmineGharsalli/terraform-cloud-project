output "db_instance_id" {
  description = "Identifier of the RDS instance."
  value       = aws_db_instance.this.id
}

output "db_instance_arn" {
  description = "ARN of the RDS instance."
  value       = aws_db_instance.this.arn
}

output "db_address" {
  description = "DNS hostname of the RDS instance (without port)."
  value       = aws_db_instance.this.address
}

output "db_endpoint" {
  description = "Connection endpoint (host:port) of the RDS instance."
  value       = aws_db_instance.this.endpoint
}

output "db_port" {
  description = "Port of the RDS instance."
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "db_resource_id" {
  description = "Immutable, unique identifier of the RDS instance."
  value       = aws_db_instance.this.resource_id
}

output "db_subnet_group_name" {
  description = "Name of the database subnet group."
  value       = aws_db_subnet_group.this.name
}
