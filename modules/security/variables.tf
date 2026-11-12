variable "name_prefix" {
  description = "Prefix used to name every resource, e.g. \"cloud5-dev\"."
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC where the security groups are created."
  type        = string
}

variable "enable_https" {
  description = "If true, the ALB security group also allows inbound HTTPS (443) from the Internet."
  type        = bool
  default     = false
}

variable "lab_role_name" {
  description = "Name of the pre-existing IAM role provided by the AWS Academy Learner Lab. Creating IAM roles is forbidden in the lab."
  type        = string
  default     = "LabRole"
}

variable "lab_instance_profile_name" {
  description = "Name of the pre-existing IAM instance profile provided by the AWS Academy Learner Lab. Creating instance profiles is forbidden in the lab."
  type        = string
  default     = "LabInstanceProfile"
}

variable "tags" {
  description = "Common tags applied to every resource of the module."
  type        = map(string)
  default     = {}
}
