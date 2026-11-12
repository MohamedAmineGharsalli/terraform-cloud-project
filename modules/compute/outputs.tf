output "asg_name" {
  description = "Name of the Auto Scaling Group. Consumed by the environment output and the failover/scaling test scripts."
  value       = aws_autoscaling_group.this.name
}

output "launch_template_id" {
  description = "ID of the launch template (useful for verification and the report)."
  value       = aws_launch_template.this.id
}
