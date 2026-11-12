variable "name_prefix" {
  description = "Prefix used to name every resource, e.g. \"cloud5-dev\"."
  type        = string
}

variable "db_subnet_ids" {
  description = "IDs of the private database subnets (from the network module). At least two, in two AZs."
  type        = list(string)

  validation {
    condition     = length(var.db_subnet_ids) >= 2
    error_message = "At least two database subnets (in two AZs) are required."
  }
}

variable "db_security_group_id" {
  description = "ID of the database security group (from the security module)."
  type        = string
}

variable "db_name" {
  description = "Name of the initial database created inside the instance."
  type        = string
  default     = "cloud5db"

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]{0,62}$", var.db_name))
    error_message = "db_name must start with a lowercase letter and contain only lowercase letters, digits and underscores."
  }
}

variable "db_username" {
  description = "Master username of the database. It is not a secret, but is kept out of code as a variable."
  type        = string
  default     = "cloud5admin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9_]{0,15}$", var.db_username))
    error_message = "db_username must start with a letter and be at most 16 characters."
  }
}

variable "db_password" {
  description = "Master password of the database. NEVER stored in code: supplied through TF_VAR_db_password (or the DB_PASSWORD GitHub secret)."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 41
    error_message = "db_password must be between 8 and 41 characters (RDS MySQL constraint)."
  }
}

variable "engine" {
  description = "Database engine. MySQL is used by the assignment."
  type        = string
  default     = "mysql"
}

variable "engine_version" {
  description = "Engine version. Empty string lets AWS pick the default minor version for the engine."
  type        = string
  default     = "8.0"
}

variable "instance_class" {
  description = "RDS instance class. Burstable classes are used to stay within the lab budget."
  type        = string
  default     = "db.t3.micro"

  validation {
    condition     = can(regex("^db\\.[a-z0-9]+\\.[a-z0-9]+$", var.instance_class))
    error_message = "instance_class must look like an RDS class, e.g. db.t3.micro."
  }
}

variable "allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20

  validation {
    condition     = var.allocated_storage >= 20
    error_message = "allocated_storage must be at least 20 GB (RDS MySQL minimum)."
  }
}

variable "max_allocated_storage" {
  description = "Upper limit in GB for storage autoscaling. 0 disables autoscaling (recommended in the lab to cap cost)."
  type        = number
  default     = 0
}

variable "storage_type" {
  description = "Storage type of the instance."
  type        = string
  default     = "gp3"
}

variable "multi_az" {
  description = "If true, the database is deployed across two AZs (high availability). false in dev/test (cheaper), true in prod."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Number of days of automated backups. 0 disables backups."
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 0 && var.backup_retention_period <= 35
    error_message = "backup_retention_period must be between 0 and 35 days."
  }
}

variable "backup_window" {
  description = "Preferred backup window (UTC)."
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window (UTC)."
  type        = string
  default     = "sun:04:30-sun:05:30"
}

variable "skip_final_snapshot" {
  description = "If true, no final snapshot is taken on destroy (dev/test). Must be false in prod, with final_snapshot_identifier set."
  type        = bool
  default     = true
}

variable "final_snapshot_identifier" {
  description = "Name of the final snapshot taken on destroy. Required when skip_final_snapshot = false."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "If true, the instance cannot be deleted while the flag is set (prod)."
  type        = bool
  default     = false
}

variable "apply_immediately" {
  description = "If true, modifications are applied immediately instead of during the maintenance window. Useful in dev/test."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Common tags applied to every resource of the module."
  type        = map(string)
  default     = {}
}
