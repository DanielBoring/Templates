/*
  Parameter File: Windows Server VM — Production
  ================================================
  Deployment target : rg-compute-prod (East US)
  VM name           : vm-app-prod-eus-01  (auto-generated)
  OS                : Windows Server 2022 Datacenter Azure Edition
  Purpose           : Application server in the production spoke.
                      Joined to Entra ID, monitored via AMA, Antimalware enabled.
                      Azure Hybrid Benefit applied (bring-your-own Windows Server licence).

  Secrets:
    adminUsername and adminPassword MUST be supplied via environment variables.
    Set before running:
      $env:VM_ADMIN_USER     = 'azureadmin'
      $env:VM_ADMIN_PASSWORD = 'P@ssw0rd!ChangeMe'

  Deploy:
    az deployment group create \
      --resource-group rg-compute-prod \
      --template-file ../main.bicep \
      --parameters @vm-windows-prod.bicepparam
*/

using '../main.bicep'

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
param environment  = 'prod'
param location     = 'eastus'
param workloadName = 'app'
param instanceNumber = '01'

// ---------------------------------------------------------------------------
// OS & Image
// ---------------------------------------------------------------------------
param osType = 'Windows'
param vmSize = 'Standard_D4s_v5'

param imageReference = {
  publisher : 'MicrosoftWindowsServer'
  offer     : 'WindowsServer'
  sku       : '2022-datacenter-azure-edition'
  version   : 'latest'
}

param availabilityZone = 1   // Pin to zone 1 for HA with zone 2 secondary

// ---------------------------------------------------------------------------
// Authentication  (read from environment variables — never hard-code secrets)
// ---------------------------------------------------------------------------
param adminUsername = readEnvironmentVariable('VM_ADMIN_USER', 'azureadmin')
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')

// ---------------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------------
// Replace with the actual subnet resource ID
param subnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-spoke-prod/providers/Microsoft.Network/virtualNetworks/vnet-spoke-app-prod-eus/subnets/snet-app'

param privateIPAllocationMethod = 'Dynamic'
param enablePublicIP            = false
param enableAcceleratedNetworking = true

// ---------------------------------------------------------------------------
// OS Disk
// ---------------------------------------------------------------------------
param osDiskStorageAccountType = 'Premium_LRS'
param osDiskSizeGB             = 128    // Override image default (usually 127 GB)
param osDiskCaching            = 'ReadWrite'

// ---------------------------------------------------------------------------
// Data Disks
// ---------------------------------------------------------------------------
param dataDisks = [
  {
    diskSizeGB           : 256
    lun                  : 0
    storageAccountType   : 'Premium_LRS'
    caching              : 'ReadOnly'    // Recommended for app/data disks
  }
]

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------
param enableAzureMonitorAgent    = true
param enableDependencyAgent      = true
param enableNetworkWatcherAgent  = true
param enableAntimalware          = true   // Enable on Windows production VMs
param enableEntraIdJoin          = true   // Join to Microsoft Entra ID

// ---------------------------------------------------------------------------
// Windows-specific
// ---------------------------------------------------------------------------
param windowsPatchMode        = 'AutomaticByPlatform'
param enableAutomaticUpdates  = true
param timeZone                = 'Eastern Standard Time'
param licenseType             = 'Windows_Server'   // Azure Hybrid Benefit

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------
param enableBootDiagnostics             = true
param logAnalyticsWorkspaceResourceId   = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/law-platform-prod'
param diagnosticRetentionDays           = 90

// ---------------------------------------------------------------------------
// Governance
// ---------------------------------------------------------------------------
param resourceLock = 'CanNotDelete'

// ---------------------------------------------------------------------------
// Mandatory Tags
// ---------------------------------------------------------------------------
param mandatoryTags = {
  CostCenter   : 'CC-APP-TEAM-042'
  Owner        : 'app-team@contoso.com'
  BusinessUnit : 'Application Services'
}

param additionalTags = {
  Criticality   : 'High'
  DataClass     : 'Confidential'
  Application   : 'Order Management System'
  PatchGroup    : 'Wave1-Sunday-2AM'
}
