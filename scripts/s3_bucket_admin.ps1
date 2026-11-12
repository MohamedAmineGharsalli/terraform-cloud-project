<#
.SYNOPSIS
  Creates or destroys an S3 bucket with the AWS CLI (storage module helper).

.DESCRIPTION
  The AWS Academy Learner Lab SCP blocks s3:GetBucketObjectLockConfiguration, so
  the Terraform aws_s3_bucket resource cannot be used. This script performs the
  equivalent operations with the AWS CLI and is invoked from a Terraform
  local-exec provisioner (create) and a destroy-time local-exec provisioner.

  Actions:
    create  -> aws s3api create-bucket (idempotent)
    destroy -> deletes every object version and delete marker, then the bucket

  Because a destroy-time provisioner can only read `self.input`, the script is
  called with explicit -Bucket / -Region arguments.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File s3_bucket_admin.ps1 -Action create -Bucket my-bucket -Region us-east-1
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][ValidateSet('create', 'destroy')][string]$Action,
  [Parameter(Mandatory = $true)][string]$Bucket,
  [Parameter(Mandatory = $true)][string]$Region
)

$ErrorActionPreference = 'Stop'

function Invoke-Aws {
  param([Parameter(Mandatory = $true)][string[]]$Command)
  & aws @Command
  if ($LASTEXITCODE -ne 0) {
    throw "aws $($Command -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Test-BucketExists {
  # head-bucket writes to stderr when the bucket is missing (404). With
  # $ErrorActionPreference = 'Stop' PowerShell would turn that native stderr
  # into a terminating error, so it is silenced around the probe only.
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'SilentlyContinue'
  try {
    & aws s3api head-bucket --bucket $Bucket --region $Region 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
  }
  finally {
    $ErrorActionPreference = $previous
  }
}

if ($Action -eq 'create') {
  if (Test-BucketExists) {
    Write-Host "Bucket '$Bucket' already exists, nothing to do."
    exit 0
  }

  if ($Region -eq 'us-east-1') {
    # LocationConstraint must NOT be passed in us-east-1.
    Invoke-Aws -Command @('s3api', 'create-bucket', '--bucket', $Bucket, '--region', $Region)
  }
  else {
    Invoke-Aws -Command @(
      's3api', 'create-bucket', '--bucket', $Bucket, '--region', $Region,
      '--create-bucket-configuration', "LocationConstraint=$Region"
    )
  }

  Write-Host "Bucket '$Bucket' created in $Region."
  exit 0
}

# --- destroy ---------------------------------------------------------------
if (-not (Test-BucketExists)) {
  Write-Host "Bucket '$Bucket' does not exist, nothing to delete."
  exit 0
}

# A versioned bucket refuses to be deleted while versions or delete markers
# remain, so both are removed first.
foreach ($kind in @('Versions', 'DeleteMarkers')) {
  while ($true) {
    $lines = @(& aws s3api list-object-versions --bucket $Bucket --region $Region `
        --query "$kind[].[Key,VersionId]" --output text 2>$null)
    if ($LASTEXITCODE -ne 0) {
      throw "aws s3api list-object-versions ($kind) failed with exit code $LASTEXITCODE"
    }

    # The AWS CLI prints the literal string "None" (not an empty string) when
    # the --query matches nothing, so it must be filtered out explicitly.
    $items = @($lines | Where-Object { $_ -and $_ -ne 'None' })
    if ($items.Count -eq 0) { break }

    foreach ($line in $items) {
      $parts = $line -split "`t"
      if ($parts.Count -lt 2) { continue }
      Invoke-Aws -Command @(
        's3api', 'delete-object', '--bucket', $Bucket, '--region', $Region,
        '--key', $parts[0], '--version-id', $parts[1]
      )
    }
  }
}

# Unversioned leftovers (if versioning was never enabled).
Invoke-Aws -Command @('s3', 'rm', "s3://$Bucket", '--recursive', '--region', $Region)
Invoke-Aws -Command @('s3api', 'delete-bucket', '--bucket', $Bucket, '--region', $Region)

Write-Host "Bucket '$Bucket' deleted."
exit 0
