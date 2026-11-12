variable "name_prefix" {
  description = "Prefix used to name the bucket, e.g. \"cloud5-dev\"."
  type        = string
}

variable "bucket_name" {
  description = "Explicit bucket name. If empty, \"<name_prefix>-storage-<account_id>\" is used (globally unique per account)."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region of the bucket. Must match the provider region. The Learner Lab only allows us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "enable_versioning" {
  description = "If true, object versioning is enabled on the bucket."
  type        = bool
  default     = true
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm: AES256 (SSE-S3) or aws:kms (SSE-KMS, requires kms_master_key_id)."
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "aws:kms", "aws:kms:dsse"], var.sse_algorithm)
    error_message = "sse_algorithm must be one of: AES256, aws:kms, aws:kms:dsse."
  }
}

variable "kms_master_key_id" {
  description = "ARN of the KMS key. Required when sse_algorithm = aws:kms."
  type        = string
  default     = ""
}

variable "block_public_access" {
  description = "If true, all four public access block settings are enabled (recommended)."
  type        = bool
  default     = true
}

variable "enable_lifecycle" {
  description = "If true, a lifecycle configuration is applied (abort incomplete multipart uploads, expire noncurrent versions)."
  type        = bool
  default     = true
}

variable "noncurrent_version_expiration_days" {
  description = "Number of days after which noncurrent object versions expire. 0 disables this rule."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to every resource of the module."
  type        = map(string)
  default     = {}
}
