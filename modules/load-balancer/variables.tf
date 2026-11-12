variable "name_prefix" {
  description = "Prefix used to name every resource, e.g. \"cloud5-dev\"."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the load balancer is created."
  type        = string
}

variable "public_subnet_ids" {
  description = "IDs of the public subnets where the ALB is placed (at least two AZs)."
  type        = list(string)

  validation {
    condition     = length(var.public_subnet_ids) >= 2
    error_message = "At least two public subnets are required for a highly available ALB."
  }
}

variable "alb_security_group_id" {
  description = "ID of the ALB security group (from the security module)."
  type        = string
}

variable "enable_https" {
  description = "If true, an HTTPS (443) listener is created and HTTP is redirected to HTTPS. Requires certificate_arn."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate used by the HTTPS listener. Required when enable_https = true."
  type        = string
  default     = ""
}

variable "health_check_path" {
  description = "Path used by the target group health check."
  type        = string
  default     = "/"
}

variable "tags" {
  description = "Common tags applied to every resource of the module."
  type        = map(string)
  default     = {}
}
