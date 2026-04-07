<#
.SYNOPSIS
    Deploys a Virtual Machine using the AVM wrapper module.

.DESCRIPTION
    Repeatable deployment script for the AVM Virtual Machine wrapper.
    Handles:
      - Azure login check / context switching
      - Resource group creation if it doesn't exist
      - Secret validation (warns if VM_ADMIN_PASSWORD is not set)
      - Bicep what-if (dry-run) before applying
      - Deployment with output capture
      - Optional post-deployment validation

.PARAMETER ParameterFile
    Path to the .bicepparam file for the target VM.

.PARAMETER ResourceGroupName
    Resource group to deploy into. Created if it doesn't exist.

.PARAMETER Location
    Azure region for the resource group. Required only on first creation.

.PARAMETER SubscriptionId
    Target subscription ID. Switches context if provided.

.PARAMETER WhatIf
    Runs az deployment group what-if and exits without deploying.

.PARAMETER SkipConfirmation
    Skips the interactive what-if review prompt (for CI/CD use).

.EXAMPLE
    # Set secrets, then deploy interactively
    $env:VM_ADMIN_USER     = 'azureadmin'
    $env:VM_ADMIN_PASSWORD = 'P@ssw0rd!ChangeMe'

    .\deploy.ps1 -ParameterFile ..\parameters\vm-windows-prod.bicepparam `
                 -ResourceGroupName rg-compute-prod `
                 -Location eastus

.EXAMPLE
    # CI/CD — secrets injected by pipeline, no prompts
    .\deploy.ps1 -ParameterFile ..\parameters\vm-windows-prod.bicepparam `
                 -ResourceGroupName rg-compute-prod `
                 -Location eastus `
                 -SubscriptionId "00000000-0000-0000-0000-000000000000" `
                 -SkipConfirmation

.EXAMPLE
    # Dry-run only
    .\deploy.ps1 -ParameterFile ..\parameters\vm-linux-prod.bicepparam `
                 -ResourceGroupName rg-compute-prod `
                 -Location eastus `
                 -WhatIf
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path $_ -PathType Leaf })]
    [string] $ParameterFile,

    [Parameter(Mandatory)]
    [string] $ResourceGroupName,

    [Parameter(Mandatory)]
    [string] $Location,

    [string]  $SubscriptionId    = '',
    [switch]  $WhatIf,
    [switch]  $SkipConfirmation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDir      = $PSScriptRoot
$templateFile   = Join-Path $scriptDir '..\main.bicep' | Resolve-Path
$paramFile      = Resolve-Path $ParameterFile
$deploymentName = "vm-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step ([string]$Message) {
    Write-Host "`n[*] $Message" -ForegroundColor Cyan
}

function Write-Success ([string]$Message) {
    Write-Host "[+] $Message" -ForegroundColor Green
}

function Write-Warn ([string]$Message) {
    Write-Host "[!] $Message" -ForegroundColor Yellow
}

function Invoke-Az ([string[]]$Arguments) {
    $result = az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "az CLI error (exit $LASTEXITCODE): $result"
    }
    return $result
}

# ---------------------------------------------------------------------------
# 1. Check az CLI
# ---------------------------------------------------------------------------
Write-Step 'Checking Azure CLI'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is not installed or not in PATH. Install from https://aka.ms/install-azure-cli'
}
Write-Success "Azure CLI $(az version --query '\"azure-cli\"' -o tsv) found."

# ---------------------------------------------------------------------------
# 2. Warn if VM password is not set (for Windows parameter files)
# ---------------------------------------------------------------------------
Write-Step 'Checking credential environment variables'
if ([string]::IsNullOrEmpty($env:VM_ADMIN_PASSWORD)) {
    Write-Warn 'VM_ADMIN_PASSWORD environment variable is not set.'
    Write-Warn 'If this parameter file requires a password, the deployment will fail.'
    Write-Warn 'Set it with: $env:VM_ADMIN_PASSWORD = Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText'
} else {
    Write-Success 'VM_ADMIN_PASSWORD is set.'
}

if ([string]::IsNullOrEmpty($env:VM_ADMIN_USER)) {
    Write-Warn 'VM_ADMIN_USER environment variable is not set — default "azureadmin" will be used.'
} else {
    Write-Success "VM_ADMIN_USER is set to: $env:VM_ADMIN_USER"
}

# ---------------------------------------------------------------------------
# 3. Login / context
# ---------------------------------------------------------------------------
Write-Step 'Checking Azure login state'
$account = az account show 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warn 'Not logged in — launching az login...'
    Invoke-Az 'login'
}

if ($SubscriptionId) {
    Write-Step "Switching to subscription: $SubscriptionId"
    Invoke-Az @('account', 'set', '--subscription', $SubscriptionId)
}

$currentSub = az account show --query '{id:id, name:name}' -o json | ConvertFrom-Json
Write-Success "Active subscription: $($currentSub.name) ($($currentSub.id))"

# ---------------------------------------------------------------------------
# 4. Ensure resource group exists
# ---------------------------------------------------------------------------
Write-Step "Ensuring resource group '$ResourceGroupName' exists in '$Location'"
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq 'false') {
    Write-Warn 'Resource group not found — creating it.'
    Invoke-Az @('group', 'create', '--name', $ResourceGroupName, '--location', $Location)
    Write-Success "Resource group '$ResourceGroupName' created."
} else {
    Write-Success "Resource group '$ResourceGroupName' already exists."
}

# ---------------------------------------------------------------------------
# 5. What-if
# ---------------------------------------------------------------------------
Write-Step "Running deployment what-if: $deploymentName"
az deployment group what-if `
    --resource-group  $ResourceGroupName `
    --template-file   $templateFile `
    --parameters      $paramFile `
    --name            $deploymentName

if ($WhatIf) {
    Write-Warn 'WhatIf flag set — deployment skipped.'
    exit 0
}

if (-not $SkipConfirmation) {
    $answer = Read-Host "`nReview the changes above. Proceed with deployment? [y/N]"
    if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
        Write-Warn 'Deployment cancelled by user.'
        exit 0
    }
}

# ---------------------------------------------------------------------------
# 6. Deploy
# ---------------------------------------------------------------------------
Write-Step "Deploying '$deploymentName' to '$ResourceGroupName'"
$output = az deployment group create `
    --resource-group  $ResourceGroupName `
    --template-file   $templateFile `
    --parameters      $paramFile `
    --name            $deploymentName `
    --output          json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    throw 'Deployment failed. Check the Azure portal or run: az deployment group show --name $deploymentName --resource-group $ResourceGroupName'
}

Write-Success 'Deployment succeeded!'

# ---------------------------------------------------------------------------
# 7. Output summary
# ---------------------------------------------------------------------------
$outputs = $output.properties.outputs
Write-Host "`n--- Deployment Outputs ---" -ForegroundColor White
Write-Host "VM Name          : $($outputs.name.value)"
Write-Host "VM Resource ID   : $($outputs.resourceId.value)"
Write-Host "Location         : $($outputs.location.value)"
Write-Host "Resource Group   : $($outputs.resourceGroupName.value)"

if ($outputs.systemAssignedMIPrincipalId.value) {
    Write-Host "Managed Identity : $($outputs.systemAssignedMIPrincipalId.value)"
}

Write-Host ""
Write-Host "IP Configurations:" -ForegroundColor White
foreach ($ipConfig in $outputs.ipConfigurations.value) {
    Write-Host "  - $($ipConfig.name): $($ipConfig.properties.privateIPAddress)"
}

Write-Success "Done. Deployment name: $deploymentName"
