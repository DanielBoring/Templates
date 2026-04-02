/*
  Parameter File: Linux VM — Production
  ========================================
  Deployment target : rg-compute-prod (East US)
  VM name           : vm-web-prod-eus-01  (auto-generated)
  OS                : Ubuntu 22.04 LTS Gen2
  Purpose           : Web tier VM. SSH key authentication only (no password).
                      Monitored via AMA. Network Watcher enabled.

  Secrets:
    adminUsername is read from an environment variable.
    SSH private key must be stored in Azure Key Vault or a secrets manager.
    Set before running:
      $env:VM_ADMIN_USER = 'azureadmin'

  SSH Public Key:
    Replace the placeholder sshPublicKeys value with your actual public key.
    Best practice: store the public key in source control and the private key
    only in a secrets vault.

  Deploy:
    az deployment group create \
      --resource-group rg-compute-prod \
      --template-file ../main.bicep \
      --parameters @vm-linux-prod.bicepparam
*/

using '../main.bicep'

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
param environment  = 'prod'
param location     = 'eastus'
param workloadName = 'web'
param instanceNumber = '01'

// ---------------------------------------------------------------------------
// OS & Image
// ---------------------------------------------------------------------------
param osType = 'Linux'
param vmSize = 'Standard_D2s_v5'

param imageReference = {
  publisher : 'Canonical'
  offer     : '0001-com-ubuntu-server-jammy'
  sku       : '22_04-lts-gen2'
  version   : 'latest'
}

param availabilityZone = 1

// ---------------------------------------------------------------------------
// Authentication — SSH key only, no password
// ---------------------------------------------------------------------------
param adminUsername               = readEnvironmentVariable('VM_ADMIN_USER', 'azureadmin')
param disablePasswordAuthentication = true

param sshPublicKeys = [
  {
    keyData : 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... replace-with-real-public-key'
    path    : '/home/azureadmin/.ssh/authorized_keys'
  }
]

// ---------------------------------------------------------------------------
// Networking
// ---------------------------------------------------------------------------
param subnetResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-spoke-prod/providers/Microsoft.Network/virtualNetworks/vnet-spoke-app-prod-eus/subnets/snet-web'

param privateIPAllocationMethod   = 'Dynamic'
param enablePublicIP              = false
param enableAcceleratedNetworking = true

// ---------------------------------------------------------------------------
// OS Disk
// ---------------------------------------------------------------------------
param osDiskStorageAccountType = 'Premium_LRS'
param osDiskSizeGB             = 64
param osDiskCaching            = 'ReadWrite'

// ---------------------------------------------------------------------------
// Data Disks
// ---------------------------------------------------------------------------
param dataDisks = [
  {
    diskSizeGB : 128
    lun        : 0
    caching    : 'ReadOnly'
  }
]

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------
param enableAzureMonitorAgent   = true
param enableDependencyAgent     = true
param enableNetworkWatcherAgent = true
param enableAntimalware         = false   // Linux — N/A
param enableEntraIdJoin         = false   // Entra join for Linux requires additional setup

// ---------------------------------------------------------------------------
// Linux-specific
// ---------------------------------------------------------------------------
param linuxPatchMode = 'AutomaticByPlatform'

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------
param enableBootDiagnostics           = true
param logAnalyticsWorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring-prod/providers/Microsoft.OperationalInsights/workspaces/law-platform-prod'
param diagnosticRetentionDays         = 90

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
  Criticality : 'High'
  DataClass   : 'Internal'
  Application : 'Order Management System'
  OsFamily    : 'Linux'
}
