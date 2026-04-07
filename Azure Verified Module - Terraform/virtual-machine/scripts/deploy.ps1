<#
.SYNOPSIS
    Repeatable Terraform deployment helper for the AVM VM module.

.DESCRIPTION
    Wraps terraform init / plan / apply / destroy with:
      - Pre-flight checks (tools installed, env vars set, subscription context)
      - Named plan files for auditability
      - Dry-run (plan-only) and CI skip-confirmation modes
      - Coloured status messages

.PARAMETER VarFile
    Path to the .tfvars file for this deployment.
    Default: environments/vm-windows-dev.tfvars

.PARAMETER SubscriptionId
    Azure subscription ID to target. If omitted, uses the current az login context.

.PARAMETER SkipConfirmation
    Skip the interactive apply/destroy confirmation. Use in CI/CD pipelines.

.PARAMETER WhatIf
    Run terraform plan only — do not apply.

.PARAMETER Destroy
    Run terraform destroy instead of apply.

.PARAMETER BackendConfig
    Optional path to a Terraform backend config file for remote state.

.EXAMPLE
    # Interactive dev deployment
    .\scripts\deploy.ps1

.EXAMPLE
    # Specify a var file
    .\scripts\deploy.ps1 -VarFile environments/vm-linux-dev.tfvars

.EXAMPLE
    # Dry-run (plan only)
    .\scripts\deploy.ps1 -VarFile environments/vm-windows-dev.tfvars -WhatIf

.EXAMPLE
    # CI/CD — no prompts
    .\scripts\deploy.ps1 `
      -VarFile          environments/vm-windows-dev.tfvars `
      -SubscriptionId   "00000000-0000-0000-0000-000000000000" `
      -SkipConfirmation

.EXAMPLE
    # Destroy resources
    .\scripts\deploy.ps1 -VarFile environments/vm-windows-dev.tfvars -Destroy
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $VarFile          = 'environments/vm-windows-dev.tfvars',
    [string] $SubscriptionId   = '',
    [switch] $SkipConfirmation,
    [switch] $WhatIf,
    [switch] $Destroy,
    [string] $BackendConfig    = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================
# Helpers
# ============================================================

function Write-Status  { param($msg) Write-Host "  [INFO]  $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "  [OK]    $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "  [WARN]  $msg" -ForegroundColor Yellow }
function Write-Fail    { param($msg) Write-Host "  [ERROR] $msg" -ForegroundColor Red }

function Invoke-Step {
    param([string]$Label, [scriptblock]$Command)
    Write-Status $Label
    & $Command
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Step failed: $Label (exit code $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

# ============================================================
# Navigate to the module root (parent of scripts/)
# ============================================================
$scriptDir  = Split-Path $MyInvocation.MyCommand.Path
$moduleRoot = Split-Path $scriptDir
Push-Location $moduleRoot

try {

# ============================================================
# Pre-flight — tools
# ============================================================
Write-Host "`n== Pre-flight checks ==" -ForegroundColor White

foreach ($tool in @('terraform', 'az')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Fail "'$tool' is not installed or not in PATH."
        exit 1
    }
    Write-Success "$tool found"
}

# ============================================================
# Pre-flight — credentials
# ============================================================

# Admin username — required for all deployments
if (-not $env:TF_VAR_admin_username) {
    Write-Warn "TF_VAR_admin_username is not set."
    $env:TF_VAR_admin_username = Read-Host "  Enter admin username"
}
Write-Success "TF_VAR_admin_username is set"

# Admin password — required for Windows; optional for Linux SSH VMs
if (-not $env:TF_VAR_admin_password) {
    # Try to determine OS type from the var file
    $varFileContent  = Get-Content $VarFile -Raw -ErrorAction SilentlyContinue
    $isLinuxSshOnly  = $varFileContent -match 'disable_password_authentication\s*=\s*true'

    if (-not $isLinuxSshOnly) {
        Write-Warn "TF_VAR_admin_password is not set. Required for Windows VMs."
        $securePassword  = Read-Host "  Enter admin password" -AsSecureString
        $env:TF_VAR_admin_password = $securePassword | ConvertFrom-SecureString -AsPlainText
    } else {
        Write-Status "Linux SSH-only VM detected — skipping admin password check."
    }
}
Write-Success "Credential check complete"

# ============================================================
# Subscription context
# ============================================================
if ($SubscriptionId) {
    Invoke-Step "Setting subscription to $SubscriptionId" {
        az account set --subscription $SubscriptionId
    }
}

$currentSub = (az account show --query '{id:id, name:name}' -o json | ConvertFrom-Json)
Write-Success "Subscription: $($currentSub.name) ($($currentSub.id))"

# ============================================================
# Var file check
# ============================================================
if (-not (Test-Path $VarFile)) {
    Write-Fail "Var file not found: $VarFile"
    exit 1
}
Write-Success "Var file: $VarFile"

# ============================================================
# Terraform init
# ============================================================
$initArgs = @('-input=false', '-upgrade')
if ($BackendConfig) { $initArgs += "-backend-config=$BackendConfig" }

Invoke-Step "terraform init" {
    terraform init @initArgs
}

# ============================================================
# Terraform plan
# ============================================================
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$planFile  = "tfplan-$timestamp.out"

Write-Status "Creating plan: $planFile"

if ($Destroy) {
    Invoke-Step "terraform plan -destroy" {
        terraform plan `
            -var-file="$VarFile" `
            -destroy `
            -out="$planFile" `
            -input=false
    }
} else {
    Invoke-Step "terraform plan" {
        terraform plan `
            -var-file="$VarFile" `
            -out="$planFile" `
            -input=false
    }
}

# ============================================================
# What-if (plan-only) exit
# ============================================================
if ($WhatIf) {
    Write-Success "WhatIf mode — plan complete. No resources were changed."
    Remove-Item $planFile -ErrorAction SilentlyContinue
    exit 0
}

# ============================================================
# Confirmation
# ============================================================
if (-not $SkipConfirmation) {
    $action = $Destroy ? 'DESTROY' : 'APPLY'
    Write-Host ""
    Write-Warn "You are about to $action resources using: $VarFile"
    Write-Host "  Review the plan output above carefully." -ForegroundColor Yellow
    Write-Host ""
    $confirm = Read-Host "  Type 'yes' to proceed, anything else to cancel"
    if ($confirm -ne 'yes') {
        Write-Warn "Cancelled by user."
        Remove-Item $planFile -ErrorAction SilentlyContinue
        exit 0
    }
}

# ============================================================
# Terraform apply / destroy
# ============================================================
$verb = $Destroy ? 'destroy' : 'apply'
Invoke-Step "terraform $verb" {
    terraform apply -input=false "$planFile"
}

# Clean up plan file after successful apply
Remove-Item $planFile -ErrorAction SilentlyContinue

Write-Host ""
Write-Success "Deployment complete."
Write-Status  "Run 'terraform output' to see resource details."

} finally {
    Pop-Location
}
