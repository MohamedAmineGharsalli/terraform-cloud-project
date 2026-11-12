# ---------------------------------------------------------------------------
# dev environment - variables and defaults.
#
# Defaults are tuned for a cheap development environment:
#   - one shared NAT gateway
#   - single-AZ database, short backup retention, no final snapshot
#
# Override any value with a terraform.tfvars file (see terraform.tfvars.example).
# ---------------------------------------------------------------------------

variable "project_name" {
  description = "Project name used as a prefix for every resource and shown on the web page."
  type        = string
  default     = "cloud5"
}

variable "aws_region" {
  description = "AWS region. The Learner Lab only allows us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "single_nat_gateway" {
  description = "true = one shared NAT gateway (cheap, dev); false = one per AZ (HA, prod)."
  type        = bool
  default     = true
}

variable "enable_https" {
  description = "Enable the HTTPS listener (requires a domain and an ACM certificate)."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ARN of the ACM certificate. Required when enable_https = true."
  type        = string
  default     = ""
}

# --- Compute ---------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  description = "Minimum number of application instances."
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Maximum number of application instances."
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Desired number of application instances."
  type        = number
  default     = 2
}

variable "cpu_target_value" {
  description = "Target average CPU (%) for the target-tracking scaling policy."
  type        = number
  default     = 50
}

variable "use_ssm_ami" {
  description = "Resolve the Amazon Linux 2023 AMI through SSM. Set to false if the SCP blocks SSM reads."
  type        = bool
  default     = true
}

# --- Database --------------------------------------------------------------
variable "db_name" {
  description = "Name of the initial database."
  type        = string
  default     = "cloud5db"
}

variable "db_username" {
  description = "Master username of the database."
  type        = string
  default     = "cloud5admin"
}

variable "db_password" {
  description = "Master password. NEVER stored in code: supplied through TF_VAR_db_password (local) or the DB_PASSWORD GitHub secret (CI)."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Allocated storage in GB."
  type        = number
  default     = 20
}

variable "db_multi_az" {
  description = "Deploy the database across two AZs (HA)."
  type        = bool
  default     = false
}

variable "db_backup_retention" {
  description = "Number of days of automated backups."
  type        = number
  default     = 1
}

variable "db_skip_final_snapshot" {
  description = "Skip the final snapshot on destroy (true in dev/test, false in prod)."
  type        = bool
  default     = true
}

variable "db_final_snapshot_identifier" {
  description = "Name of the final snapshot. Required when db_skip_final_snapshot = false."
  type        = string
  default     = ""
}

variable "db_deletion_protection" {
  description = "Prevent accidental deletion of the database."
  type        = bool
  default     = false
}

variable "db_apply_immediately" {
  description = "Apply database modifications immediately instead of during the maintenance window."
  type        = bool
  default     = true
}

# --- Storage ---------------------------------------------------------------
variable "bucket_name" {
  description = "Explicit S3 bucket name. Empty = <name_prefix>-storage-<account_id>."
  type        = string
  default     = ""
}

variable "enable_versioning" {
  description = "Enable S3 object versioning."
  type        = bool
  default     = true
}

# --- Tags ------------------------------------------------------------------
variable "tags" {
  description = "Additional tags applied to every resource."
  type        = map(string)
  default     = {}
}
