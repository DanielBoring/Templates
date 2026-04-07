/*
  Entry Point: Virtual Machine Deployment
  =========================================
  Orchestration layer. Calls the vm-wrapper module and exposes top-level outputs.
  This file is what you target with "az deployment group create".

  Usage:
    az deployment group create \
      --resource-group rg-compute-prod \
      --template-file main.bicep \
      --parameters @parameters/vm-windows-prod.bicepparam

  Or via the deploy.ps1 helper script (recommended — handles state checks and what-if).
*/

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters  (mirror all wrapper params so .bicepparam files bind here)
// ---------------------------------------------------------------------------

@description('Short environment identifier.')
@allowed(['prod', 'nonprod', 'dev', 'test', 'staging'])
param environment string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Override the auto-generated VM name. Leave empty to use naming convention.')
param nameOverride string = ''

@description('Short workload name. e.g. dc, web, app, sql, mgmt.')
param workloadName string

@description('Two-digit instance number. e.g. 01, 02.')
@minLength(2)
@maxLength(2)
param instanceNumber string = '01'

@description('Optional OS hostname override. Windows max 15 chars.')
param computerName string = ''

@description('OS type: Windows or Linux.')
@allowed(['Windows', 'Linux'])
param osType string

@description('VM SKU. e.g. Standard_D2s_v5.')
param vmSize string = 'Standard_D2s_v5'

@description('OS image reference. See wrapper module for examples.')
param imageReference object

@description('Availability zone. 0 = no zone pinning.')
@minValue(0)
@maxValue(3)
param availabilityZone int = 0

@secure()
@description('Local administrator username.')
param adminUsername string

@secure()
@description('Local administrator password. For Linux SSH-only, leave empty.')
param adminPassword string = ''

@description('Disable password auth for Linux SSH-only VMs.')
param disablePasswordAuthentication bool = false

@description('SSH public keys for Linux VMs.')
param sshPublicKeys array = []

@description('Subnet resource ID for the primary NIC.')
param subnetResourceId string

@description('Private IP allocation method.')
@allowed(['Dynamic', 'Static'])
param privateIPAllocationMethod string = 'Dynamic'

@description('Static private IP. Required if privateIPAllocationMethod is Static.')
param staticPrivateIPAddress string = ''

@description('Attach a public IP. Avoid in production.')
param enablePublicIP bool = false

@description('Enable accelerated networking on the NIC.')
param enableAcceleratedNetworking bool = true

@description('OS disk storage SKU.')
@allowed(['Premium_LRS', 'Premium_ZRS', 'StandardSSD_LRS', 'StandardSSD_ZRS', 'Standard_LRS'])
param osDiskStorageAccountType string = 'Premium_LRS'

@description('OS disk size in GB. 0 = use image default.')
@minValue(0)
param osDiskSizeGB int = 0

@description('OS disk caching mode.')
@allowed(['None', 'ReadOnly', 'ReadWrite'])
param osDiskCaching string = 'ReadWrite'

@description('Data disk definitions array. See README for schema.')
param dataDisks array = []

@description('Install Azure Monitor Agent.')
param enableAzureMonitorAgent bool = true

@description('Install VM Insights Dependency Agent.')
param enableDependencyAgent bool = true

@description('Install Network Watcher Agent.')
param enableNetworkWatcherAgent bool = true

@description('Install Microsoft Antimalware. Windows only.')
param enableAntimalware bool = false

@description('Join the VM to Microsoft Entra ID.')
param enableEntraIdJoin bool = false

@description('Enable system-assigned managed identity.')
param enableSystemAssignedIdentity bool = true

@description('User-assigned managed identity resource IDs.')
param userAssignedIdentityResourceIds array = []

@description('Windows patch mode. Ignored for Linux.')
@allowed(['AutomaticByOS', 'AutomaticByPlatform', 'Manual'])
param windowsPatchMode string = 'AutomaticByPlatform'

@description('Enable automatic Windows updates. Ignored for Linux.')
param enableAutomaticUpdates bool = true

@description('Windows time zone. e.g. AUS Eastern Standard Time. Empty = UTC.')
param timeZone string = ''

@description('Windows Hybrid Benefit license type. Empty = PAYG.')
param licenseType string = ''

@description('Linux patch mode. Ignored for Windows.')
@allowed(['AutomaticByPlatform', 'ImageDefault'])
param linuxPatchMode string = 'AutomaticByPlatform'

@description('Enable boot diagnostics with managed storage.')
param enableBootDiagnostics bool = true

@description('Log Analytics Workspace resource ID for diagnostics. Empty = skip.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Diagnostic log retention days.')
@minValue(7)
@maxValue(365)
param diagnosticRetentionDays int = 30

@description('Resource lock level.')
@allowed(['None', 'CanNotDelete', 'ReadOnly'])
param resourceLock string = 'None'

@description('RBAC role assignments for the VM.')
param roleAssignments array = []

@description('Disable AVM telemetry if required by policy.')
param enableTelemetry bool = true

@description('Mandatory organisational tags. Must include CostCenter, Owner, and BusinessUnit.')
param mandatoryTags object

@description('Optional extra tags.')
param additionalTags object = {}

// ---------------------------------------------------------------------------
// Module Call
// ---------------------------------------------------------------------------

module vm './modules/vm-wrapper.bicep' = {
  name: 'vm-deployment'
  params: {
    environment                       : environment
    location                          : location
    nameOverride                      : nameOverride
    workloadName                      : workloadName
    instanceNumber                    : instanceNumber
    computerName                      : computerName
    osType                            : osType
    vmSize                            : vmSize
    imageReference                    : imageReference
    availabilityZone                  : availabilityZone
    adminUsername                     : adminUsername
    adminPassword                     : adminPassword
    disablePasswordAuthentication     : disablePasswordAuthentication
    sshPublicKeys                     : sshPublicKeys
    subnetResourceId                  : subnetResourceId
    privateIPAllocationMethod         : privateIPAllocationMethod
    staticPrivateIPAddress            : staticPrivateIPAddress
    enablePublicIP                    : enablePublicIP
    enableAcceleratedNetworking       : enableAcceleratedNetworking
    osDiskStorageAccountType          : osDiskStorageAccountType
    osDiskSizeGB                      : osDiskSizeGB
    osDiskCaching                     : osDiskCaching
    dataDisks                         : dataDisks
    enableAzureMonitorAgent           : enableAzureMonitorAgent
    enableDependencyAgent             : enableDependencyAgent
    enableNetworkWatcherAgent         : enableNetworkWatcherAgent
    enableAntimalware                 : enableAntimalware
    enableEntraIdJoin                 : enableEntraIdJoin
    enableSystemAssignedIdentity      : enableSystemAssignedIdentity
    userAssignedIdentityResourceIds   : userAssignedIdentityResourceIds
    windowsPatchMode                  : windowsPatchMode
    enableAutomaticUpdates            : enableAutomaticUpdates
    timeZone                          : timeZone
    licenseType                       : licenseType
    linuxPatchMode                    : linuxPatchMode
    enableBootDiagnostics             : enableBootDiagnostics
    logAnalyticsWorkspaceResourceId   : logAnalyticsWorkspaceResourceId
    diagnosticRetentionDays           : diagnosticRetentionDays
    resourceLock                      : resourceLock
    roleAssignments                   : roleAssignments
    enableTelemetry                   : enableTelemetry
    mandatoryTags                     : mandatoryTags
    additionalTags                    : additionalTags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Virtual Machine.')
output resourceId string = vm.outputs.resourceId

@description('Name of the Virtual Machine.')
output name string = vm.outputs.name

@description('Location of the Virtual Machine.')
output location string = vm.outputs.location

@description('Resource group name.')
output resourceGroupName string = vm.outputs.resourceGroupName

@description('Primary NIC IP configurations.')
output ipConfigurations array = vm.outputs.ipConfigurations

@description('System-assigned managed identity principal ID.')
output systemAssignedMIPrincipalId string = vm.outputs.systemAssignedMIPrincipalId
