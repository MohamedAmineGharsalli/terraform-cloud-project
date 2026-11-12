output "alb_security_group_id" {
  description = "ID of the ALB security group. Consumed by the load-balancer module."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "ID of the application security group. Consumed by the compute module."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "ID of the database security group. Consumed by the database module."
  value       = aws_security_group.db.id
}

output "lab_instance_profile_name" {
  description = "Name of the pre-existing Learner Lab instance profile. Consumed by the compute module."
  value       = data.aws_iam_instance_profile.lab_instance_profile.name
}

output "lab_role_arn" {
  description = "ARN of the pre-existing Learner Lab role (LabRole), for documentation and verification."
  value       = data.aws_iam_role.lab_role.arn
}
