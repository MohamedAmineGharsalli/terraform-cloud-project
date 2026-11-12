output "name_prefix" {
  description = "Prefix used to name every resource of this environment."
  value       = local.name_prefix
}

output "website_url" {
  description = "URL of the web application (through the load balancer)."
  value       = var.enable_https ? "https://${module.load_balancer.alb_dns_name}" : "http://${module.load_balancer.alb_dns_name}"
}

output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer."
  value       = module.load_balancer.alb_dns_name
}

output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "app_subnet_ids" {
  description = "IDs of the private application subnets."
  value       = module.network.app_subnet_ids
}

output "asg_name" {
  description = "Name of the Auto Scaling Group."
  value       = module.compute.asg_name
}

output "db_endpoint" {
  description = "Connection endpoint (host:port) of the database."
  value       = module.database.db_endpoint
}

output "db_address" {
  description = "DNS hostname of the database."
  value       = module.database.db_address
}

output "db_name" {
  description = "Name of the initial database."
  value       = module.database.db_name
}

output "bucket_id" {
  description = "Name of the S3 bucket."
  value       = module.storage.bucket_id
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = module.storage.bucket_arn
}

output "lab_role_arn" {
  description = "ARN of the pre-existing Learner Lab role (LabRole)."
  value       = module.security.lab_role_arn
}
