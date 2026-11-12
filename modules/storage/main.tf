# ---------------------------------------------------------------------------
# Storage module: private S3 bucket.
#
# WHY local-exec?
#   The AWS Academy Learner Lab SCP blocks s3:GetBucketObjectLockConfiguration.
#   The aws_s3_bucket resource reads that setting, so it fails with every
#   provider version. The bucket is therefore created through the AWS CLI in a
#   terraform_data resource, which keeps it in the Terraform state.
#
#   Cross-platform: the create/destroy commands are chosen at plan time from
#   pathexpand("~") (Windows vs Linux) and call either
#   scripts/s3_bucket_admin.ps1 (powershell.exe) or
#   scripts/s3_bucket_admin.sh (bash).
#
#   A destroy-time provisioner may only reference `self`, so the OS flag and the
#   bucket/region are stored in `input`.
#
# The bucket sub-resources (versioning, encryption, public access block,
# lifecycle) call different S3 APIs and are managed natively by Terraform.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  # Windows: pathexpand("~") = "C:\Users\..."; Linux: "/home/...".
  is_windows = substr(pathexpand("~"), 0, 1) != "/"

  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.name_prefix}-storage-${data.aws_caller_identity.current.account_id}"

  create_command = local.is_windows ? "powershell -NoProfile -ExecutionPolicy Bypass -File \"${path.module}/../../scripts/s3_bucket_admin.ps1\" -Action create -Bucket ${local.bucket_name} -Region ${var.aws_region}" : "bash \"${path.module}/../../scripts/s3_bucket_admin.sh\" create ${local.bucket_name} ${var.aws_region}"
}

# The bucket itself, created outside the S3 provider (see header).
resource "terraform_data" "bucket" {
  input = {
    bucket     = local.bucket_name
    region     = var.aws_region
    is_windows = local.is_windows
  }

  provisioner "local-exec" {
    command = local.create_command
  }

  # Destroy-time provisioners may only read `self`, hence self.input.*.
  provisioner "local-exec" {
    when    = destroy
    command = self.input.is_windows ? "powershell -NoProfile -ExecutionPolicy Bypass -File \"${path.module}/../../scripts/s3_bucket_admin.ps1\" -Action destroy -Bucket ${self.input.bucket} -Region ${self.input.region}" : "bash \"${path.module}/../../scripts/s3_bucket_admin.sh\" destroy ${self.input.bucket} ${self.input.region}"
  }
}

# ---------------------------------------------------------------------------
# Bucket sub-resources (native Terraform management)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  count = var.enable_versioning ? 1 : 0

  bucket = terraform_data.bucket.output.bucket

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = terraform_data.bucket.output.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "AES256" ? null : var.kms_master_key_id
    }

    bucket_key_enabled = var.sse_algorithm == "AES256" ? false : true
  }

  lifecycle {
    precondition {
      condition     = var.sse_algorithm == "AES256" || length(var.kms_master_key_id) > 0
      error_message = "kms_master_key_id must be set when sse_algorithm is aws:kms or aws:kms:dsse."
    }
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = var.block_public_access ? 1 : 0

  bucket = terraform_data.bucket.output.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = var.enable_lifecycle ? 1 : 0

  bucket = terraform_data.bucket.output.bucket

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  dynamic "rule" {
    for_each = var.noncurrent_version_expiration_days > 0 ? [1] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
