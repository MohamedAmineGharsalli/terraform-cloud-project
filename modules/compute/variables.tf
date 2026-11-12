variable "name_prefix" {
  description = "Prefix used to name every resource, e.g. \"cloud5-dev\"."
  type        = string
}

variable "project_name" {
  description = "Project name shown on the demo web page served by the instances."
  type        = string
}

variable "app_subnet_ids" {
  description = "IDs of the private application subnets where instances are launched."
  type        = list(string)

  validation {
    condition     = length(var.app_subnet_ids) >= 2
    error_message = "At least two application subnets are required for high availability."
  }
}

variable "app_security_group_id" {
  description = "ID of the application security group (from the security module)."
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the pre-existing Learner Lab instance profile (from the security module)."
  type        = string
}

variable "target_group_arn" {
  description = "ARN of the ALB target group the Auto Scaling Group is attached to."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type. Small burstable types are used to stay within the lab budget."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z]{1,2}[0-9][a-z]?\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must look like an EC2 type, e.g. t3.micro, m5.large, c5n.xlarge."
  }
}

variable "min_size" {
  description = "Minimum number of instances in the Auto Scaling Group."
  type        = number
  default     = 2

  validation {
    condition     = var.min_size >= 2
    error_message = "min_size must be >= 2 for high availability."
  }
}

variable "max_size" {
  description = "Maximum number of instances in the Auto Scaling Group."
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of instances at creation time."
  type        = number
  default     = 2
}

variable "root_volume_size" {
  description = "Size in GB of the encrypted gp3 root volume."
  type        = number
  default     = 8
}

variable "cpu_target_value" {
  description = "Target average CPU utilisation (%) for the target-tracking scaling policy."
  type        = number
  default     = 50
}

variable "use_ssm_ami" {
  description = "If true, resolve the Amazon Linux 2023 AMI through the public SSM parameter. Set to false to use the aws_ami data source as a fallback if the SCP blocks SSM parameter reads."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to every resource of the module."
  type        = map(string)
  default     = {}
}
