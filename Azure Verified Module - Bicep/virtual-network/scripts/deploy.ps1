<#
.SYNOPSIS
    Deploys a Virtual Network using the AVM wrapper module.

.DESCRIPTION
    Repeatable deployment script for the AVM Virtual Network wrapper.
    Handles:
      - Azure login check / context switching
      - Resource group creation if it doesn't exist
      - Bicep what-if (dry-run) before applying
      - Deployment with output capture
      - Optional post-deployment validation

.PARAMETER ParameterFile
    Path to the .bicepparam file for the target VNet.

.PARAMETER ResourceGroupName
    Resource group to deploy into. Created if it doesn't exist.

.PARAMETER Location
    Azure region for the resource group. Required only on first creation.
    Ignored if the resource group already exists.

.PARAMETER SubscriptionId
    Target subscription ID. Switches context if provided.

.PARAMETER WhatIf
    Runs az deployment group what-if and exits without deploying.

.PARAMETER SkipConfirmation
    Skips the interactive what-if review prompt (for CI/CD use).

.EXAMPLE
    # Interactive deployment with what-if preview
    .\deploy.ps1 -ParameterFile ..\parameters\vnet-hub-prod.bicepparam `
                 -ResourceGroupName rg-networking-prod `
                 -Location eastus

.EXAMPLE
    # CI/CD pipeline — no prompts
    .\deploy.ps1 -ParameterFile ..\parameters\vnet-spoke-prod.bicepparam `
                 -ResourceGroupName rg-networking-spoke-prod `
                 -Location eastus `
                 -SubscriptionId "00000000-0000-0000-0000-000000000000" `
                 -SkipConfirmation

.EXAMPLE
    # Dry-run only — do not deploy
    .\deploy.ps1 -ParameterFile ..\parameters\vnet-spoke-dev.bicepparam `
                 -ResourceGroupName rg-networking-spoke-dev `
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

# Resolve paths relative to this script
$scriptDir    = $PSScriptRoot
$templateFile = Join-Path $scriptDir '..\main.bicep' | Resolve-Path
$paramFile    = Resolve-Path $ParameterFile

$deploymentName = "vnet-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

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
# 1. Check az CLI is available
# ---------------------------------------------------------------------------
Write-Step 'Checking Azure CLI'
if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is not installed or not in PATH. Install from https://aka.ms/install-azure-cli'
}
Write-Success "Azure CLI $(az version --query '\"azure-cli\"' -o tsv) found."

# ---------------------------------------------------------------------------
# 2. Login / context
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
# 3. Ensure resource group exists
# ---------------------------------------------------------------------------
Write-Step "Ensuring resource group '$ResourceGroupName' exists in '$Location'"
$rgExists = az group exists --name $ResourceGroupName
if ($rgExists -eq 'false') {
    Write-Warn "Resource group not found — creating it."
    Invoke-Az @('group', 'create', '--name', $ResourceGroupName, '--location', $Location)
    Write-Success "Resource group '$ResourceGroupName' created."
} else {
    Write-Success "Resource group '$ResourceGroupName' already exists."
}

# ---------------------------------------------------------------------------
# 4. What-if (always shown unless -SkipConfirmation in CI)
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
# 5. Deploy
# ---------------------------------------------------------------------------
Write-Step "Deploying '$deploymentName' to '$ResourceGroupName'"
$output = az deployment group create `
    --resource-group  $ResourceGroupName `
    --template-file   $templateFile `
    --parameters      $paramFile `
    --name            $deploymentName `
    --output          json | ConvertFrom-Json

if ($LASTEXITCODE -ne 0) {
    throw "Deployment failed. Check the Azure portal for details."
}

Write-Success 'Deployment succeeded!'

# ---------------------------------------------------------------------------
# 6. Output summary
# ---------------------------------------------------------------------------
$outputs = $output.properties.outputs
Write-Host "`n--- Deployment Outputs ---" -ForegroundColor White
Write-Host "VNet Name        : $($outputs.name.value)"
Write-Host "VNet Resource ID : $($outputs.resourceId.value)"
Write-Host "Location         : $($outputs.location.value)"
Write-Host "Resource Group   : $($outputs.resourceGroupName.value)"
Write-Host ""
Write-Host "Subnets:" -ForegroundColor White
foreach ($subnetId in $outputs.subnetResourceIds.value) {
    $subnetName = ($subnetId -split '/')[-1]
    Write-Host "  - $subnetName"
    Write-Host "    $subnetId"
}

Write-Success "Done. Deployment name: $deploymentName"
