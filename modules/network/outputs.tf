output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ALB), ordered by AZ. Consumed by the load-balancer module."
  value       = [for k in sort(keys(local.public_subnets)) : aws_subnet.this[k].id]
}

output "app_subnet_ids" {
  description = "IDs of the private application subnets (EC2), ordered by AZ. Consumed by the compute module."
  value       = [for k in sort(keys(local.app_subnets)) : aws_subnet.this[k].id]
}

output "db_subnet_ids" {
  description = "IDs of the private database subnets (RDS), ordered by AZ. Consumed by the database module."
  value       = [for k in sort(keys(local.db_subnets)) : aws_subnet.this[k].id]
}
