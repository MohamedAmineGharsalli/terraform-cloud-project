# ---------------------------------------------------------------------------
# Storage module: private S3 bucket.
#
# WHY local-exec?
#   The AWS Academy Learner Lab SCP blocks s3:GetBucketObjectLockConfiguration.
#   The aws_s3_bucket resource reads that setting, so it fails with every
#   provider version. The bucket is therefore created through the AWS CLI in a
#   terraform_data resource, which keeps it in the Terraform state.
#
#   Cross-platform: the CREATE command is chosen at plan time from
#   pathexpand("~") (Windows vs Linux) and calls either
#   scripts/s3_bucket_admin.ps1 (powershell.exe) or
#   scripts/s3_bucket_admin.sh (bash).
#
#   The DESTROY command is OS-AGNOSTIC: it tries PowerShell first and falls back
#   to bash with `||` ("powershell ... || bash ..."). A destroy-time provisioner
#   may only reference `self` (plus `path.module`), so the OS cannot be read from
#   a local at destroy time. Keeping `input` free of any OS flag also guarantees
#   that applying on Windows and destroying on Linux (CI) never changes `input`,
#   which would make terraform_data REPLACE itself and delete the bucket.
#
#   PATH QUOTING: on Windows Terraform runs the command through `cmd /C` and Go
#   quotes the whole argument; embedded double quotes are turned into a literal
#   `\"` that powershell.exe receives verbatim and rejects with "Caracteres non
#   conformes dans le chemin d'acces". The script paths are therefore built with
#   abspath() (which already yields forward slashes on Windows) and left
#   UNQUOTED. The repository path contains no spaces.
#
# The bucket sub-resources (versioning, encryption, public access block,
# lifecycle) call different S3 APIs and are managed natively by Terraform.
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  # Windows: pathexpand("~") = "C:\Users\..."; Linux: "/home/...".
  # Used ONLY to pick the create command (the destroy command is OS-agnostic).
  is_windows = substr(pathexpand("~"), 0, 1) != "/"

  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.name_prefix}-storage-${data.aws_caller_identity.current.account_id}"

  # Absolute, forward-slash, UNQUOTED script paths (see PATH QUOTING above).
  ps1_script = abspath("${path.module}/../../scripts/s3_bucket_admin.ps1")
  sh_script  = abspath("${path.module}/../../scripts/s3_bucket_admin.sh")

  create_command = local.is_windows ? "powershell -NoProfile -ExecutionPolicy Bypass -File ${local.ps1_script} -Action create -Bucket ${local.bucket_name} -Region ${var.aws_region}" : "bash ${local.sh_script} create ${local.bucket_name} ${var.aws_region}"
}

# The bucket itself, created outside the S3 provider (see header).
resource "terraform_data" "bucket" {
  # Only stable values: a change here would REPLACE the resource (and delete the
  # bucket). Never add an OS flag or anything environment-dependent.
  input = {
    bucket = local.bucket_name
    region = var.aws_region
  }

  provisioner "local-exec" {
    command = local.create_command
  }

  # Destroy-time provisioners may only read `self` and `path.module`, hence
  # self.input.* and abspath(path.module). The `||` fallback makes the command
  # work on Windows (cmd.exe) and Linux (/bin/sh) without storing the OS in
  # `input`. Paths are unquoted (see PATH QUOTING in the header).
  provisioner "local-exec" {
    when    = destroy
    command = "powershell -NoProfile -ExecutionPolicy Bypass -File ${abspath("${path.module}/../../scripts/s3_bucket_admin.ps1")} -Action destroy -Bucket ${self.input.bucket} -Region ${self.input.region} || bash ${abspath("${path.module}/../../scripts/s3_bucket_admin.sh")} destroy ${self.input.bucket} ${self.input.region}"
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
