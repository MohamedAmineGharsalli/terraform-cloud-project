#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# s3_bucket_admin.sh - create or destroy an S3 bucket with the AWS CLI.
#
# The AWS Academy Learner Lab SCP blocks s3:GetBucketObjectLockConfiguration,
# so the Terraform aws_s3_bucket resource cannot be used. This script performs
# the equivalent operations and is invoked from a Terraform local-exec
# provisioner (create) and a destroy-time local-exec provisioner (destroy).
#
# Because a destroy-time provisioner can only read `self.input`, the script is
# called with explicit bucket and region arguments.
#
# Usage: s3_bucket_admin.sh <create|destroy> <bucket> <region>
# ---------------------------------------------------------------------------
set -euo pipefail

ACTION="${1:-}"
BUCKET="${2:-}"
REGION="${3:-}"

if [ -z "$ACTION" ] || [ -z "$BUCKET" ] || [ -z "$REGION" ]; then
  echo "Usage: $0 <create|destroy> <bucket> <region>" >&2
  exit 2
fi

bucket_exists() {
  aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null 2>&1
}

if [ "$ACTION" = "create" ]; then
  if bucket_exists; then
    echo "Bucket '$BUCKET' already exists, nothing to do."
    exit 0
  fi

  if [ "$REGION" = "us-east-1" ]; then
    # LocationConstraint must NOT be passed in us-east-1.
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi

  echo "Bucket '$BUCKET' created in $REGION."
  exit 0
fi

if [ "$ACTION" = "destroy" ]; then
  if ! bucket_exists; then
    echo "Bucket '$BUCKET' does not exist, nothing to delete."
    exit 0
  fi

  # A versioned bucket refuses to be deleted while versions or delete markers
  # remain, so both are removed first.
  for kind in Versions DeleteMarkers; do
    while true; do
      lines="$(aws s3api list-object-versions --bucket "$BUCKET" --region "$REGION" \
        --query "${kind}[].[Key,VersionId]" --output text)"
      # The AWS CLI prints the literal string "None" (not an empty string) when
      # the --query matches nothing, so it must be filtered out explicitly.
      if [ -z "$lines" ] || [ "$lines" = "None" ]; then
        break
      fi
      while IFS=$'\t' read -r key version_id; do
        if [ -z "$key" ] || [ "$key" = "None" ]; then
          continue
        fi
        aws s3api delete-object --bucket "$BUCKET" --region "$REGION" \
          --key "$key" --version-id "$version_id" >/dev/null
      done <<< "$lines"
    done
  done

  # Unversioned leftovers (if versioning was never enabled).
  aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" || true
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"

  echo "Bucket '$BUCKET' deleted."
  exit 0
fi

echo "Unknown action: $ACTION" >&2
exit 2
