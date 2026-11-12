#Requires -Version 5.1
<#
.SYNOPSIS
    Cree (si besoin) et securise le bucket S3 servant de backend Terraform distant.

.DESCRIPTION
    La creation du bucket d'etat via la ressource Terraform aws_s3_bucket est
    impossible dans l'AWS Academy Learner Lab : le SCP du lab refuse l'action
    s3:GetBucketObjectLockConfiguration, donc la ressource echoue a la creation
    avec TOUTES les versions du provider. Ce script AWS CLI contourne le SCP.

    Le script est IDEMPOTENT : il peut etre relance autant de fois que necessaire.

    Il applique les quatre protections suivantes :
      1. Versioning active
      2. Chiffrement par defaut SSE-S3 (AES256) + bucket key
      3. Blocage total de l'acces public (les 4 options)
      4. Politique de bucket refusant toute requete non TLS (aws:SecureTransport = false)

.PARAMETER BucketName
    Nom du bucket d'etat. Si omis, il est calcule depuis l'account id :
    <ProjectName>-tfstate-<account_id>.

.PARAMETER ProjectName
    Prefixe du nom de bucket. Doit correspondre a project_name des environnements.
    Defaut : cloud5.

.PARAMETER Region
    Region AWS. Defaut : us-east-1 (seule region utilisable dans le lab).

.EXAMPLE
    ./scripts/bootstrap-backend.ps1

.EXAMPLE
    ./scripts/bootstrap-backend.ps1 -ProjectName cloud5

.EXAMPLE
    ./scripts/bootstrap-backend.ps1 -BucketName cloud5-tfstate-123456789012
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$BucketName = "",

    [Parameter(Mandatory = $false)]
    [string]$ProjectName = "cloud5",

    [Parameter(Mandatory = $false)]
    [string]$Region = "us-east-1"
)

$ErrorActionPreference = "Stop"

function Invoke-Aws {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
    aws @Args
    if ($LASTEXITCODE -ne 0) {
        throw "La commande AWS a echoue (code $LASTEXITCODE) : aws $($Args -join ' ')"
    }
}

function New-TempJson {
    param([Parameter(Mandatory = $true)][string]$Content)
    $path = [System.IO.Path]::GetTempFileName()
    Set-Content -Path $path -Value $Content -Encoding ascii
    return $path
}

Write-Host "=== Bootstrap du backend Terraform (AWS CLI) ===" -ForegroundColor Cyan

# --- 0. Identite AWS (verifie que les identifiants du lab sont charges) -----
$identity = aws sts get-caller-identity --no-cli-pager --output json | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw "aws sts get-caller-identity a echoue : identifiants du Learner Lab absents ou expires." }
Write-Host "Compte : $($identity.Account)   Arn : $($identity.Arn)" -ForegroundColor DarkGray

# --- Nom du bucket : calcule depuis l'account id si non fourni --------------
if ([string]::IsNullOrWhiteSpace($BucketName)) {
    $BucketName = "$ProjectName-tfstate-$($identity.Account)"
}

Write-Host "Bucket : $BucketName" -ForegroundColor Cyan
Write-Host "Region : $Region" -ForegroundColor Cyan

# --- 1. Creation du bucket si absent (idempotent) ---------------------------
$previousEap = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
aws s3api head-bucket --bucket $BucketName --no-cli-pager 1>$null 2>$null
$headExit = $LASTEXITCODE
$ErrorActionPreference = $previousEap

if ($headExit -eq 0) {
    Write-Host "[1/4] Bucket deja present : creation ignoree." -ForegroundColor Yellow
}
else {
    Write-Host "[1/4] Creation du bucket ..." -ForegroundColor Green
    if ($Region -eq "us-east-1") {
        # En us-east-1, il ne faut PAS passer de LocationConstraint.
        Invoke-Aws s3api create-bucket --bucket $BucketName --region $Region --no-cli-pager
    }
    else {
        Invoke-Aws s3api create-bucket --bucket $BucketName --region $Region `
            --create-bucket-configuration "LocationConstraint=$Region" --no-cli-pager
    }
}

# --- 2. Versioning ----------------------------------------------------------
Write-Host "[2/4] Activation du versioning ..." -ForegroundColor Green
Invoke-Aws s3api put-bucket-versioning --bucket $BucketName `
    --versioning-configuration "Status=Enabled" --no-cli-pager

# --- 3. Chiffrement SSE-S3 --------------------------------------------------
Write-Host "[3/4] Chiffrement par defaut (SSE-S3 / AES256) ..." -ForegroundColor Green
$encryptionJson = @'
{
  "Rules": [
    {
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "AES256"
      },
      "BucketKeyEnabled": true
    }
  ]
}
'@
$encryptionFile = New-TempJson -Content $encryptionJson
try {
    Invoke-Aws s3api put-bucket-encryption --bucket $BucketName `
        --server-side-encryption-configuration "file://$encryptionFile" --no-cli-pager
}
finally {
    Remove-Item -Force $encryptionFile -ErrorAction SilentlyContinue
}

# --- 3bis. Blocage de l'acces public ----------------------------------------
Write-Host "[3/4] Blocage de l'acces public ..." -ForegroundColor Green
Invoke-Aws s3api put-public-access-block --bucket $BucketName `
    --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" `
    --no-cli-pager

# --- 4. Politique TLS uniquement --------------------------------------------
Write-Host "[4/4] Politique : refus des requetes non TLS ..." -ForegroundColor Green
$policyJson = @"
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyInsecureTransport",
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::$BucketName",
        "arn:aws:s3:::$BucketName/*"
      ],
      "Condition": {
        "Bool": {
          "aws:SecureTransport": "false"
        }
      }
    }
  ]
}
"@
$policyFile = New-TempJson -Content $policyJson
try {
    Invoke-Aws s3api put-bucket-policy --bucket $BucketName `
        --policy "file://$policyFile" --no-cli-pager
}
finally {
    Remove-Item -Force $policyFile -ErrorAction SilentlyContinue
}

# --- Verification finale ----------------------------------------------------
Write-Host ""
Write-Host "=== Verification ===" -ForegroundColor Cyan
$versioning = aws s3api get-bucket-versioning --bucket $BucketName --no-cli-pager --output json | ConvertFrom-Json
$publicBlock = aws s3api get-public-access-block --bucket $BucketName --no-cli-pager --output json | ConvertFrom-Json

Write-Host ("Versioning  : {0}" -f $versioning.Status)
Write-Host ("Public block: BlockPublicAcls={0} IgnorePublicAcls={1} BlockPublicPolicy={2} RestrictPublicBuckets={3}" -f `
        $publicBlock.PublicAccessBlockConfiguration.BlockPublicAcls, `
        $publicBlock.PublicAccessBlockConfiguration.IgnorePublicAcls, `
        $publicBlock.PublicAccessBlockConfiguration.BlockPublicPolicy, `
        $publicBlock.PublicAccessBlockConfiguration.RestrictPublicBuckets)

Write-Host ""
Write-Host "Termine. Bucket d'etat pret : $BucketName" -ForegroundColor Green
Write-Host "Les environnements peuvent maintenant faire : terraform init" -ForegroundColor Green
