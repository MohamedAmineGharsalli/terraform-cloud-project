output "bucket_id" {
  description = "Name (id) of the S3 bucket. Known at plan time."
  value       = local.bucket_name
}

output "bucket_arn" {
  description = "ARN of the S3 bucket."
  value       = "arn:aws:s3:::${local.bucket_name}"
}

output "bucket_domain_name" {
  description = "Global domain name of the bucket."
  value       = "${local.bucket_name}.s3.amazonaws.com"
}

output "bucket_regional_domain_name" {
  description = "Region-specific domain name of the bucket."
  value       = "${local.bucket_name}.s3.${var.aws_region}.amazonaws.com"
}
