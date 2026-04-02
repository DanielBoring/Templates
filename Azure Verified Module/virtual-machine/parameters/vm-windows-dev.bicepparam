/*
  Parameter File: Windows Server VM — Development
  =================================================
  Deployment target : rg-compute-dev (East US)
  VM name           : vm-app-dev-eus-01  (auto-generated)
  OS                : Windows Server 2022 Datacenter Azure Edition
  Purpose           : Developer workstation / integration test VM.
                      Smaller SKU, no zone pinning, no lock, shorter log retention.
                      No Antimalware or Entra join to keep deployment fast.

  Secrets:
    $env:VM_ADMIN_USER     = 'azureadmin'
    $env:VM_ADMIN_PASSWORD = 'P@ssw0rd!Dev'

  Deploy:
    az deployment group create \
      --resource-group rg-compute-dev \
      --template-file ../main.bicep \
      --parameters @vm-windows-dev.bicepparam
*/

using '../main.bicep'

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
param environment  = 'dev'
param location     = 'eastus'
param workloadName = 'app'
param instanceNumber = '01'

// ---------------------------------------------------------------------------
// OS & Image
// ---------------------------------------------------------------------------
param osType = 'Windows'
param vmSize = 'Standard_B2ms'   // Burstable — cost-effective for dev

param imageReference = {
  publisher : 'MicrosoftWindowsServer'
  offer     : 'WindowsServer'
  sku       : '2022-datacenter-azure-edition'
  version   : 'latest'
}

param availabilityZone = 0   // No zone pinning needed in dev

// ---------------------------------------------------------------------------
// Authentication
// ---------------------------------------------------------------------------
param adminUsername = readEnvironmentVariable('VM_ADMIN_USER', 'azureadmin')
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')

// ---------------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------------
param subnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-spoke-dev/providers/Microsoft.Network/virtualNetworks/vnet-spoke-app-dev-eus/subnets/snet-app'

param privateIPAllocationMethod   = 'Dynamic'
param enablePublicIP              = false
param enableAcceleratedNetworking = false   // B-series doesn't support accelerated networking

// ---------------------------------------------------------------------------
// OS Disk
// ---------------------------------------------------------------------------
param osDiskStorageAccountType = 'StandardSSD_LRS'   // Cheaper than Premium for dev
param osDiskSizeGB             = 0                    // Use image default
param osDiskCaching            = 'ReadWrite'

// ---------------------------------------------------------------------------
// Data Disks
// ---------------------------------------------------------------------------
param dataDisks = []   // No data disks needed for dev

// ---------------------------------------------------------------------------
// Extensions — lean set for dev
// ---------------------------------------------------------------------------
param enableAzureMonitorAgent   = true    // Keep monitoring even in dev
param enableDependencyAgent     = false   // Skip in dev — reduces cost
param enableNetworkWatcherAgent = true
param enableAntimalware         = false
param enableEntraIdJoin         = false

// ---------------------------------------------------------------------------
// Windows-specific
// ---------------------------------------------------------------------------
param windowsPatchMode        = 'AutomaticByOS'   // Simpler in dev
param enableAutomaticUpdates  = true
param timeZone                = 'Eastern Standard Time'
param licenseType             = 'Windows_Server'  // AHUB applies in dev too if licensed

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------
param enableBootDiagnostics           = true
param logAnalyticsWorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring-dev/providers/Microsoft.OperationalInsights/workspaces/law-platform-dev'
param diagnosticRetentionDays         = 30   // Short retention for dev

// ---------------------------------------------------------------------------
// Governance — no lock in dev
// ---------------------------------------------------------------------------
param resourceLock = 'None'

// ---------------------------------------------------------------------------
// Mandatory Tags
// ---------------------------------------------------------------------------
param mandatoryTags = {
  CostCenter   : 'CC-APP-TEAM-042'
  Owner        : 'app-team@contoso.com'
  BusinessUnit : 'Application Services'
}

param additionalTags = {
  Criticality : 'Low'
  DataClass   : 'Internal'
  AutoShutdown : '1900'   // Used by an Azure Policy / automation runbook
}
