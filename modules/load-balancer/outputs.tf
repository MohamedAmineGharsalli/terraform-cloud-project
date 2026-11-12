output "alb_dns_name" {
  description = "Public DNS name of the Application Load Balancer. Consumed by the environment output."
  value       = aws_lb.this.dns_name
}

output "target_group_arn" {
  description = "ARN of the target group. Consumed by the compute module to attach the Auto Scaling Group."
  value       = aws_lb_target_group.this.arn
}
