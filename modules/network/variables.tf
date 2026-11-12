variable "name_prefix" {
  description = "Prefix used to name every resource, e.g. \"cloud5-dev\"."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. The six subnets are derived from it with cidrsubnet()."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.20.0.0/16."
  }

  validation {
    condition     = can(regex("/([1-9]|1[0-6])$", var.vpc_cidr))
    error_message = "vpc_cidr prefix length must be between /1 and /16 so that /24 subnets fit."
  }
}

variable "single_nat_gateway" {
  description = "If true, one NAT gateway is shared by all app subnets (cheaper, dev/test). If false, one NAT gateway per AZ (high availability, prod)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags applied to every resource of the module."
  type        = map(string)
  default     = {}
}
