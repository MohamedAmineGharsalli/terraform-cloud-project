#Requires -Version 5.1
<#
.SYNOPSIS
    Suite de tests du projet cloud5 (Terraform + scripts).

.DESCRIPTION
    Verifie, sans rien deployer :

      terraform : terraform fmt -check, terraform validate (6 modules + 3 envs),
                  rendu du template user_data.sh
      scripts   : fins de ligne LF, syntaxe bash (bash -n), arguments des scripts
                  s3_bucket_admin.{ps1,sh}, contenu de user_data.sh
      aws       : (optionnel, -IncludeAws) identite AWS, bucket d'etat, cycle de
                  vie complet d'un bucket versionne temporaire

    Par defaut, seules les suites "terraform" et "scripts" sont executees : elles
    ne necessitent ni identifiants AWS ni ressources cloud.

.PARAMETER Suite
    Suite a executer : all (defaut), terraform, scripts ou aws.

.PARAMETER IncludeAws
    Avec -Suite all, execute aussi la suite "aws" (necessite des identifiants).

.PARAMETER LogDir
    Repertoire du journal (defaut : docs/tests).

.PARAMETER NoLog
    N'ecrit aucun journal.

.EXAMPLE
    pwsh tests/run-tests.ps1

.EXAMPLE
    pwsh tests/run-tests.ps1 -Suite all -IncludeAws

.NOTES
    Code de sortie : 0 si tous les tests passent, 1 sinon.
#>
[CmdletBinding()]
param(
    [ValidateSet('all', 'terraform', 'scripts', 'aws')]
    [string]$Suite = 'all',

    [switch]$IncludeAws,

    [string]$LogDir = 'docs/tests',

    [switch]$NoLog
)

$ErrorActionPreference = 'Stop'

$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$script:RunningOnWindows = ($env:OS -eq 'Windows_NT')
$script:Passed = 0
$script:Failed = 0
$script:Results = New-Object System.Collections.Generic.List[object]
$script:AccountId = $null
$script:LogPath = $null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ("=== {0} ===" -f $Title) -ForegroundColor Cyan
}

function Write-Skip {
    param([string]$Message)
    Write-Host ("  (skip) {0}" -f $Message) -ForegroundColor Yellow
}

function Invoke-Case {
    param(
        [Parameter(Mandatory = $true)][string]$Suite,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Body
    )
    Write-Host ("  - {0} ... " -f $Name) -NoNewline
    try {
        & $Body
        Write-Host 'OK' -ForegroundColor Green
        $script:Passed++
        $script:Results.Add([pscustomobject]@{ Suite = $Suite; Name = $Name; Status = 'PASS'; Detail = '' })
    }
    catch {
        Write-Host 'FAIL' -ForegroundColor Red
        Write-Host ("      {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:Failed++
        $script:Results.Add([pscustomobject]@{ Suite = $Suite; Name = $Name; Status = 'FAIL'; Detail = $_.Exception.Message })
    }
}

function Assert-True {
    param([Parameter(Mandatory = $true)][bool]$Condition, [string]$Message = 'assertion failed')
    if (-not $Condition) { throw $Message }
}

function Get-ToolPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

# Runs a native command and returns its exit code and merged output. Native
# stderr is captured instead of being promoted to a terminating error.
function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [string[]]$Arguments = @(),
        [string]$WorkingDirectory
    )
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $pushed = $false
    try {
        if ($WorkingDirectory) { Push-Location -LiteralPath $WorkingDirectory; $pushed = $true }
        $output = & $File @Arguments 2>&1 | Out-String
        $code = $LASTEXITCODE
    }
    finally {
        if ($pushed) { Pop-Location }
        $ErrorActionPreference = $previous
    }
    return [pscustomobject]@{ Output = $output; ExitCode = $code }
}

# Returns the PowerShell executable able to run the project scripts.
function Get-PowerShellHost {
    foreach ($name in @('pwsh', 'powershell')) {
        $path = Get-ToolPath $name
        if ($path) { return $path }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Suite: terraform
# ---------------------------------------------------------------------------
function Test-TerraformSuite {
    Write-Section 'terraform'

    $terraform = Get-ToolPath 'terraform'
    if (-not $terraform) {
        Invoke-Case 'terraform' 'terraform available' { throw 'terraform introuvable dans le PATH' }
        return
    }

    Invoke-Case 'terraform' 'fmt -check -recursive' {
        $r = Invoke-Native $terraform @('fmt', '-check', '-recursive') $script:RepoRoot
        Assert-True ($r.ExitCode -eq 0) ("des fichiers ne sont pas formates :`n" + $r.Output)
    }

    $dirs = @()
    foreach ($root in @('modules', 'environments')) {
        $full = Join-Path $script:RepoRoot $root
        if (Test-Path $full) {
            $dirs += Get-ChildItem -Path $full -Directory | Sort-Object Name |
                ForEach-Object { "$root/$($_.Name)" }
        }
    }

    foreach ($dir in $dirs) {
        Invoke-Case 'terraform' ("validate {0}" -f $dir) {
            $work = Join-Path $script:RepoRoot $dir
            $init = Invoke-Native $terraform @('init', '-backend=false', '-input=false', '-no-color') $work
            Assert-True ($init.ExitCode -eq 0) ("terraform init a echoue pour {0} :`n{1}" -f $dir, $init.Output)
            $validate = Invoke-Native $terraform @('validate', '-no-color') $work
            Assert-True ($validate.ExitCode -eq 0) ("terraform validate a echoue pour {0} :`n{1}" -f $dir, $validate.Output)
        }
    }

    Invoke-Case 'terraform' 'rendu du template user_data.sh' {
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("cloud5-render-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $tmp | Out-Null
        try {
            Set-Content -Path (Join-Path $tmp 'main.tf') -Value 'terraform {}' -Encoding ascii
            $init = Invoke-Native $terraform @('init', '-input=false', '-no-color') $tmp
            Assert-True ($init.ExitCode -eq 0) ("init (rendu) a echoue :`n" + $init.Output)

            $template = (Join-Path $script:RepoRoot 'scripts/user_data.sh') -replace '\\', '/'
            $expression = 'templatefile("{0}", {{ project_name = "cloud5" }})' -f $template

            $previous = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                $rendered = $expression | & $terraform console 2>&1 | Out-String
                $code = $LASTEXITCODE
            }
            finally { $ErrorActionPreference = $previous }

            Assert-True ($code -eq 0) ("terraform console a echoue :`n" + $rendered)
            Assert-True ($rendered -match 'cloud5') "la variable project_name n'a pas ete substituee"
            Assert-True ($rendered -notmatch '\$\{project_name\}') "le placeholder \${project_name} est encore present"
            Assert-True ($rendered -match 'nginx') "le script n'installe pas nginx"
        }
        finally {
            Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Suite: scripts
# ---------------------------------------------------------------------------
function Test-ScriptsSuite {
    Write-Section 'scripts'

    $scriptsDir = Join-Path $script:RepoRoot 'scripts'
    $shellScripts = @(Get-ChildItem -Path $scriptsDir -Filter '*.sh' -File | Sort-Object Name)

    foreach ($file in $shellScripts) {
        Invoke-Case 'scripts' ("fin de ligne LF : scripts/{0}" -f $file.Name) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            Assert-True (-not ($bytes -contains [byte]13)) 'un octet CR (0x0D) a ete trouve : le fichier doit rester en LF'
        }
    }

    $bash = Get-ToolPath 'bash'
    if ($bash) {
        foreach ($file in $shellScripts) {
            Invoke-Case 'scripts' ("bash -n scripts/{0}" -f $file.Name) {
                # Run from the scripts directory and pass the bare file name:
                # bash on Windows mangles absolute Windows paths (backslashes).
                $r = Invoke-Native $bash @('-n', $file.Name) $scriptsDir
                Assert-True ($r.ExitCode -eq 0) $r.Output
            }
        }
    }
    else {
        Write-Skip 'bash introuvable : verification de syntaxe bash ignoree'
    }

    $userDataPath = Join-Path $scriptsDir 'user_data.sh'
    if (Test-Path $userDataPath) {
        Invoke-Case 'scripts' 'user_data.sh : jeton IMDSv2 (metadata)' {
            $content = Get-Content -Path $userDataPath -Raw
            Assert-True ($content -match 'latest/api/token') 'aucun appel au endpoint IMDSv2 /latest/api/token'
            Assert-True ($content -match 'X-aws-ec2-metadata-token') 'aucun en-tete X-aws-ec2-metadata-token'
        }

        Invoke-Case 'scripts' 'user_data.sh : placeholder Terraform ${project_name}' {
            $content = Get-Content -Path $userDataPath -Raw
            Assert-True ($content -match '\$\{project_name\}') 'le placeholder ${project_name} est absent'
        }
    }

    $psHost = Get-PowerShellHost
    if ($psHost) {
        $adminScript = Join-Path $scriptsDir 's3_bucket_admin.ps1'

        Invoke-Case 'scripts' 's3_bucket_admin.ps1 : action invalide rejetee' {
            $r = Invoke-Native $psHost @('-NoProfile', '-File', $adminScript, '-Action', 'bogus', '-Bucket', 'x', '-Region', 'us-east-1') $script:RepoRoot
            Assert-True ($r.ExitCode -ne 0) 'une action inconnue aurait du etre refusee'
        }

        Invoke-Case 'scripts' 's3_bucket_admin.ps1 : arguments obligatoires' {
            $r = Invoke-Native $psHost @('-NoProfile', '-File', $adminScript, '-Action', 'create', '-Region', 'us-east-1') $script:RepoRoot
            Assert-True ($r.ExitCode -ne 0) 'le parametre -Bucket manquant aurait du etre refuse'
        }
    }
    else {
        Write-Skip 'aucun hote PowerShell (pwsh/powershell) : tests du script .ps1 ignores'
    }

    if ($bash) {
        $shName = 's3_bucket_admin.sh'

        Invoke-Case 'scripts' 's3_bucket_admin.sh : usage si arguments manquants' {
            $r = Invoke-Native $bash @($shName) $scriptsDir
            Assert-True ($r.ExitCode -eq 2) ("code de sortie attendu 2, obtenu {0}" -f $r.ExitCode)
            Assert-True ($r.Output -match 'Usage') 'le message d''usage est absent'
        }

        Invoke-Case 'scripts' 's3_bucket_admin.sh : action inconnue rejetee' {
            $r = Invoke-Native $bash @($shName, 'bogus', 'bucket', 'us-east-1') $scriptsDir
            Assert-True ($r.ExitCode -eq 2) ("code de sortie attendu 2, obtenu {0}" -f $r.ExitCode)
            Assert-True ($r.Output -match 'Unknown action') 'le message d''erreur est absent'
        }
    }
}

# ---------------------------------------------------------------------------
# Suite: aws (optionnelle)
# ---------------------------------------------------------------------------
function Remove-TestBucket {
    param([string]$Bucket)
    $psHost = Get-PowerShellHost
    $bash = Get-ToolPath 'bash'
    $scriptsDir = Join-Path $script:RepoRoot 'scripts'
    $ps1 = Join-Path $scriptsDir 's3_bucket_admin.ps1'

    if ($script:RunningOnWindows -and $psHost) {
        Invoke-Native $psHost @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1, '-Action', 'destroy', '-Bucket', $Bucket, '-Region', 'us-east-1') $script:RepoRoot | Out-Null
    }
    elseif ($bash) {
        Invoke-Native $bash @('s3_bucket_admin.sh', 'destroy', $Bucket, 'us-east-1') $scriptsDir | Out-Null
    }
}

function Test-AwsSuite {
    Write-Section 'aws'

    $aws = Get-ToolPath 'aws'
    if (-not $aws) {
        Invoke-Case 'aws' 'aws CLI disponible' { throw 'aws CLI introuvable dans le PATH' }
        return
    }

    $identityOk = $true
    Invoke-Case 'aws' 'aws sts get-caller-identity' {
        $r = Invoke-Native $aws @('sts', 'get-caller-identity', '--output', 'json', '--no-cli-pager') $script:RepoRoot
        Assert-True ($r.ExitCode -eq 0) ("identifiants absents ou expires :`n" + $r.Output)
        $script:AccountId = ($r.Output | ConvertFrom-Json).Account
        Assert-True (-not [string]::IsNullOrWhiteSpace($script:AccountId)) 'account id introuvable'
    }
    if ($script:Failed -gt 0 -and -not $script:AccountId) { $identityOk = $false }

    if ($identityOk) {
        $stateBucket = "cloud5-tfstate-$($script:AccountId)"
        Invoke-Case 'aws' ("bucket d'etat present : {0}" -f $stateBucket) {
            $r = Invoke-Native $aws @('s3api', 'head-bucket', '--bucket', $stateBucket) $script:RepoRoot
            Assert-True ($r.ExitCode -eq 0) ("bucket d'etat absent (lancez scripts/bootstrap-backend.ps1) :`n" + $r.Output)
        }

        Invoke-Case 'aws' 'cycle de vie d''un bucket versionne temporaire' {
            $bucket = "cloud5-test-tmp-$($script:AccountId)"
            $psHost = Get-PowerShellHost
            $ps1 = Join-Path $script:RepoRoot 'scripts/s3_bucket_admin.ps1'
            Assert-True ($null -ne $psHost) 'aucun hote PowerShell disponible'

            try {
                # Clean any leftover from a previous run.
                Remove-TestBucket -Bucket $bucket

                $create = Invoke-Native $psHost @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1, '-Action', 'create', '-Bucket', $bucket, '-Region', 'us-east-1') $script:RepoRoot
                Assert-True ($create.ExitCode -eq 0) ("creation echouee :`n" + $create.Output)

                $ver = Invoke-Native $aws @('s3api', 'put-bucket-versioning', '--bucket', $bucket, '--versioning-configuration', 'Status=Enabled') $script:RepoRoot
                Assert-True ($ver.ExitCode -eq 0) $ver.Output

                $tmpFile = Join-Path ([System.IO.Path]::GetTempPath()) ("cloud5-obj-" + [guid]::NewGuid().ToString('N') + '.txt')
                Set-Content -Path $tmpFile -Value 'cloud5 test object' -Encoding ascii
                try {
                    Invoke-Native $aws @('s3', 'cp', $tmpFile, "s3://$bucket/a.txt") $script:RepoRoot | Out-Null
                    Invoke-Native $aws @('s3', 'cp', $tmpFile, "s3://$bucket/a.txt") $script:RepoRoot | Out-Null
                    Invoke-Native $aws @('s3', 'rm', "s3://$bucket/a.txt") $script:RepoRoot | Out-Null
                }
                finally {
                    Remove-Item -Force $tmpFile -ErrorAction SilentlyContinue
                }

                $versions = Invoke-Native $aws @('s3api', 'list-object-versions', '--bucket', $bucket, '--query', 'length(Versions || `[]`)', '--output', 'text') $script:RepoRoot
                $markers = Invoke-Native $aws @('s3api', 'list-object-versions', '--bucket', $bucket, '--query', 'length(DeleteMarkers || `[]`)', '--output', 'text') $script:RepoRoot
                Assert-True (([int]$versions.Output.Trim()) -ge 2) ("versions attendues >= 2, obtenu '{0}'" -f $versions.Output.Trim())
                Assert-True (([int]$markers.Output.Trim()) -ge 1) ("delete markers attendus >= 1, obtenu '{0}'" -f $markers.Output.Trim())

                Remove-TestBucket -Bucket $bucket

                $head = Invoke-Native $aws @('s3api', 'head-bucket', '--bucket', $bucket) $script:RepoRoot
                Assert-True ($head.ExitCode -ne 0) 'le bucket devrait avoir ete supprime (head-bucket a reussi)'
            }
            finally {
                Remove-TestBucket -Bucket $bucket
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$runTerraform = $Suite -in @('all', 'terraform')
$runScripts = $Suite -in @('all', 'scripts')
$runAws = ($Suite -eq 'aws') -or ($Suite -eq 'all' -and $IncludeAws)

Write-Host '==========================================================' -ForegroundColor White
Write-Host ' cloud5 - suite de tests' -ForegroundColor White
Write-Host (" depot  : {0}" -f $script:RepoRoot)
Write-Host (" suites : terraform={0} scripts={1} aws={2}" -f $runTerraform, $runScripts, $runAws)
Write-Host '==========================================================' -ForegroundColor White

if (-not $NoLog) {
    $logDir = Join-Path $script:RepoRoot $LogDir
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $script:LogPath = Join-Path $logDir 'run-tests.log'
    try { Start-Transcript -Path $script:LogPath -Force | Out-Null }
    catch { Write-Skip ("journal desactive : {0}" -f $_.Exception.Message); $script:LogPath = $null }
}

try {
    if ($runTerraform) { Test-TerraformSuite }
    if ($runScripts) { Test-ScriptsSuite }
    if ($runAws) { Test-AwsSuite }

    Write-Host ''
    Write-Host '----------------------------------------------------------' -ForegroundColor White
    Write-Host (" RESULTAT : {0} reussi(s), {1} echoue(s)" -f $script:Passed, $script:Failed) -ForegroundColor White
    Write-Host '----------------------------------------------------------' -ForegroundColor White

    if ($script:Results.Count -gt 0) {
        $script:Results | Format-Table -AutoSize | Out-String | Write-Host
    }
}
finally {
    if ($script:LogPath) {
        try { Stop-Transcript | Out-Null } catch { }
        Write-Host ("Journal : {0}" -f $script:LogPath) -ForegroundColor DarkGray
    }
}

if ($script:Failed -gt 0) { exit 1 }
exit 0
