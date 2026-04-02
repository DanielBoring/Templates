/*
  AVM Wrapper Module: Virtual Machine
  =====================================
  Purpose    : Wraps the Azure Verified Module (AVM) for Virtual Machine with
               organisation-wide defaults, mandatory tagging, naming conventions,
               auto-named disks, and extension guardrails. Consumers pass only
               the values that vary per VM.

  AVM Source : br/public:avm/res/compute/virtual-machine:0.10.0
  AVM Docs   : https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/compute/virtual-machine
*/

metadata name        = 'VM AVM Wrapper'
metadata description = 'Organisation wrapper around the AVM Virtual Machine module.'
metadata owner       = 'Platform / Compute Team'

// ---------------------------------------------------------------------------
// Parameters — Identity & Naming
// ---------------------------------------------------------------------------

@description('Short environment identifier used in naming and tagging.')
@allowed(['prod', 'nonprod', 'dev', 'test', 'staging'])
param environment string

@description('Azure region for the Virtual Machine.')
param location string = resourceGroup().location

@description('Override the auto-generated VM resource name. Leave empty to use naming convention: vm-<workload>-<environment>-<locationShort>-<instance>.')
param nameOverride string = ''

@description('Short name of the workload this VM belongs to. Used in the auto-generated name. e.g. dc, web, app, sql, mgmt.')
param workloadName string

@description('Two-digit instance number appended to the generated name. e.g. 01, 02.')
@minLength(2)
@maxLength(2)
param instanceNumber string = '01'

@description('Optional override for the OS hostname (computerName). Windows limit: 15 characters. Defaults to the resource name.')
param computerName string = ''

// ---------------------------------------------------------------------------
// Parameters — OS & Image
// ---------------------------------------------------------------------------

@description('Operating system type.')
@allowed(['Windows', 'Linux'])
param osType string

@description('Azure VM SKU. e.g. Standard_D2s_v5, Standard_B2ms.')
param vmSize string = 'Standard_D2s_v5'

@description('''
OS image reference object. Examples:

  Windows Server 2022:
  {
    publisher: 'MicrosoftWindowsServer'
    offer:     'WindowsServer'
    sku:       '2022-datacenter-azure-edition'
    version:   'latest'
  }

  Ubuntu 22.04 LTS (Gen2):
  {
    publisher: 'Canonical'
    offer:     '0001-com-ubuntu-server-jammy'
    sku:       '22_04-lts-gen2'
    version:   'latest'
  }

  Red Hat Enterprise Linux 9:
  {
    publisher: 'RedHat'
    offer:     'RHEL'
    sku:       '9-lvm-gen2'
    version:   'latest'
  }
''')
param imageReference object

@description('Availability zone to pin the VM to. 0 = no zone (regional), 1/2/3 = specific zone.')
@minValue(0)
@maxValue(3)
param availabilityZone int = 0

// ---------------------------------------------------------------------------
// Parameters — Authentication
// ---------------------------------------------------------------------------

@description('Local administrator username.')
@secure()
param adminUsername string

@description('Local administrator password. Required for Windows. For Linux SSH-only, set disablePasswordAuthentication to true and supply sshPublicKeys instead.')
@secure()
param adminPassword string = ''

@description('Set true for Linux VMs that authenticate via SSH keys only (no password).')
param disablePasswordAuthentication bool = false

@description('''
SSH public key(s) for Linux VMs. Each entry requires keyData and path.

  Example:
  [
    {
      keyData : 'ssh-rsa AAAAB3NzaC1...'
      path    : '/home/azureadmin/.ssh/authorized_keys'
    }
  ]
''')
param sshPublicKeys array = []

// ---------------------------------------------------------------------------
// Parameters — Networking
// ---------------------------------------------------------------------------

@description('Resource ID of the subnet to attach the primary NIC to.')
param subnetResourceId string

@description('Private IP allocation method for the primary NIC.')
@allowed(['Dynamic', 'Static'])
param privateIPAllocationMethod string = 'Dynamic'

@description('Static private IP address. Required when privateIPAllocationMethod is Static.')
param staticPrivateIPAddress string = ''

@description('Attach a public IP to the primary NIC. Defaults to false — avoid in production.')
param enablePublicIP bool = false

@description('Enable accelerated networking on the primary NIC. Requires a supported VM SKU.')
param enableAcceleratedNetworking bool = true

// ---------------------------------------------------------------------------
// Parameters — OS Disk
// ---------------------------------------------------------------------------

@description('OS disk storage SKU.')
@allowed(['Premium_LRS', 'Premium_ZRS', 'StandardSSD_LRS', 'StandardSSD_ZRS', 'Standard_LRS'])
param osDiskStorageAccountType string = 'Premium_LRS'

@description('OS disk size in GB. Set 0 to use the image default size.')
@minValue(0)
param osDiskSizeGB int = 0

@description('OS disk caching mode.')
@allowed(['None', 'ReadOnly', 'ReadWrite'])
param osDiskCaching string = 'ReadWrite'

// ---------------------------------------------------------------------------
// Parameters — Data Disks
// ---------------------------------------------------------------------------

@description('''
Array of data disk definitions. The wrapper auto-generates disk names and sets safe defaults.
Each item supports:
  {
    diskSizeGB           : int     (required)
    lun                  : int     (optional — auto-assigned from array index if omitted)
    storageAccountType   : string  (optional — defaults to Premium_LRS)
    caching              : string  (optional — defaults to ReadOnly)
  }
''')
param dataDisks array = []

// ---------------------------------------------------------------------------
// Parameters — Extensions
// ---------------------------------------------------------------------------

@description('Install the Azure Monitor Agent (AMA). Requires system-assigned identity.')
param enableAzureMonitorAgent bool = true

@description('Install the VM Insights Dependency Agent (requires AMA).')
param enableDependencyAgent bool = true

@description('Install the Network Watcher Agent.')
param enableNetworkWatcherAgent bool = true

@description('Install Microsoft Antimalware extension. Windows only.')
param enableAntimalware bool = false

@description('Join the VM to Microsoft Entra ID (Azure AD). Enables passwordless sign-in.')
param enableEntraIdJoin bool = false

// ---------------------------------------------------------------------------
// Parameters — Identity
// ---------------------------------------------------------------------------

@description('Assign a system-managed identity to the VM. Automatically enabled when AMA is active.')
param enableSystemAssignedIdentity bool = true

@description('Resource IDs of user-assigned managed identities to attach to the VM.')
param userAssignedIdentityResourceIds array = []

// ---------------------------------------------------------------------------
// Parameters — Windows-specific
// ---------------------------------------------------------------------------

@description('Windows patch management mode. Ignored for Linux.')
@allowed(['AutomaticByOS', 'AutomaticByPlatform', 'Manual'])
param windowsPatchMode string = 'AutomaticByPlatform'

@description('Enable automatic Windows updates. Ignored for Linux.')
param enableAutomaticUpdates bool = true

@description('Windows time zone identifier. e.g. "AUS Eastern Standard Time". Leave empty for UTC.')
param timeZone string = ''

@description('Windows Azure Hybrid Benefit license type. Leave empty for PAYG. e.g. Windows_Server, Windows_Client.')
param licenseType string = ''

// ---------------------------------------------------------------------------
// Parameters — Linux-specific
// ---------------------------------------------------------------------------

@description('Linux patch management mode. Ignored for Windows.')
@allowed(['AutomaticByPlatform', 'ImageDefault'])
param linuxPatchMode string = 'AutomaticByPlatform'

// ---------------------------------------------------------------------------
// Parameters — Diagnostics & Governance
// ---------------------------------------------------------------------------

@description('Enable boot diagnostics with managed storage (no storage account required).')
param enableBootDiagnostics bool = true

@description('Resource ID of a Log Analytics Workspace for diagnostic settings. Leave empty to skip.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Retention days for diagnostic logs and metrics.')
@minValue(7)
@maxValue(365)
param diagnosticRetentionDays int = 30

@description('Resource lock level.')
@allowed(['None', 'CanNotDelete', 'ReadOnly'])
param resourceLock string = 'None'

@description('RBAC role assignments to apply to the VM resource.')
param roleAssignments array = []

@description('Set false to disable AVM telemetry.')
param enableTelemetry bool = true

@description('''
Mandatory organisational tags. Must include CostCenter, Owner, and BusinessUnit.
Wrapper merges these with auto-generated Environment and ManagedBy tags.
''')
param mandatoryTags object

@description('Additional tags merged on top of mandatory tags.')
param additionalTags object = {}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

var regionAbbreviations = {
  australiaeast      : 'aue'
  australiasoutheast : 'ause'
  eastus             : 'eus'
  eastus2            : 'eus2'
  westus             : 'wus'
  westus2            : 'wus2'
  westus3            : 'wus3'
  centralus          : 'cus'
  northcentralus     : 'ncus'
  southcentralus     : 'scus'
  westcentralus      : 'wcus'
  northeurope        : 'neu'
  westeurope         : 'weu'
  uksouth            : 'uks'
  ukwest             : 'ukw'
  southeastasia      : 'sea'
  eastasia           : 'ea'
  japaneast          : 'jpe'
  japanwest          : 'jpw'
  brazilsouth        : 'brs'
  canadacentral      : 'cac'
  canadaeast         : 'cae'
  southafricanorth   : 'san'
  centralindia       : 'cin'
  southindia         : 'sin'
  westindia          : 'win'
  koreacentral       : 'krc'
  koreasouth         : 'krs'
  francecentral      : 'frc'
  francesouth        : 'frs'
  germanywestcentral : 'gwc'
  norwayeast         : 'noe'
  switzerlandnorth   : 'chn'
  uaenorth           : 'uaen'
}

var locationShort = contains(regionAbbreviations, location) ? regionAbbreviations[location] : location

var resolvedName = !empty(nameOverride)
  ? nameOverride
  : 'vm-${workloadName}-${environment}-${locationShort}-${instanceNumber}'

var resolvedComputerName = !empty(computerName) ? computerName : resolvedName

var resolvedTags = union(
  {
    Environment : environment
    ManagedBy   : 'Bicep / AVM'
  },
  mandatoryTags,
  additionalTags
)

// NIC configuration built from simplified parameters
var nicConfigurations = [
  {
    nicSuffix    : '-nic-01'
    deleteOption : 'Delete'
    enableAcceleratedNetworking : enableAcceleratedNetworking
    ipConfigurations: [
      {
        name                       : 'ipconfig01'
        subnetResourceId           : subnetResourceId
        privateIPAllocationMethod  : privateIPAllocationMethod
        privateIPAddress           : privateIPAllocationMethod == 'Static' ? staticPrivateIPAddress : null
        pipConfiguration           : enablePublicIP
          ? { publicIpNameSuffix: '-pip-01', zones: availabilityZone != 0 ? [availabilityZone] : [] }
          : null
      }
    ]
  }
]

// OS disk built from simplified parameters
var osDisk = union(
  {
    name          : '${resolvedName}-osdisk'
    caching       : osDiskCaching
    createOption  : 'FromImage'
    deleteOption  : 'Delete'
    managedDisk   : { storageAccountType: osDiskStorageAccountType }
  },
  osDiskSizeGB != 0 ? { diskSizeGB: osDiskSizeGB } : {}
)

// Data disks — auto-generate names and fill in defaults
var resolvedDataDisks = [for (disk, i) in dataDisks: union(
  {
    name               : '${resolvedName}-datadisk-${padLeft(string(i + 1), 2, '0')}'
    diskSizeGB         : disk.diskSizeGB
    lun                : contains(disk, 'lun') ? disk.lun : i
    caching            : contains(disk, 'caching') ? disk.caching : 'ReadOnly'
    createOption       : 'Empty'
    deleteOption       : 'Delete'
    managedDisk        : { storageAccountType: contains(disk, 'storageAccountType') ? disk.storageAccountType : 'Premium_LRS' }
  },
  {}
)]

// Diagnostic settings
var diagnosticSettings = !empty(logAnalyticsWorkspaceResourceId)
  ? [
      {
        name                  : 'diag-${resolvedName}'
        workspaceResourceId   : logAnalyticsWorkspaceResourceId
        metricCategories      : [{ category: 'AllMetrics', retentionPolicy: { days: diagnosticRetentionDays, enabled: true } }]
      }
    ]
  : []

// Resource lock
var lockConfig = resourceLock != 'None'
  ? { kind: resourceLock, name: 'lock-${resolvedName}' }
  : null

// Managed identity — system-assigned is required for AMA
var managedIdentities = {
  systemAssigned           : enableSystemAssignedIdentity || enableAzureMonitorAgent
  userAssignedResourceIds  : userAssignedIdentityResourceIds
}

// Extensions
var extensionMonitoringAgentConfig = enableAzureMonitorAgent
  ? { enabled: true }
  : {}

var extensionDependencyAgentConfig = enableDependencyAgent
  ? { enabled: true, enableAMA: true }
  : {}

var extensionNetworkWatcherAgentConfig = enableNetworkWatcherAgent
  ? { enabled: true }
  : {}

var extensionAntimalwareConfig = enableAntimalware && osType == 'Windows'
  ? {
      enabled  : true
      settings : {
        AntimalwareEnabled        : 'true'
        RealtimeProtectionEnabled : 'true'
        ScheduledScanSettings     : {
          isEnabled : 'true'
          day       : '7'
          time      : '120'
          scanType  : 'Quick'
        }
      }
    }
  : {}

var extensionAadJoinConfig = enableEntraIdJoin
  ? { enabled: true }
  : {}

// ---------------------------------------------------------------------------
// AVM Module Call
// ---------------------------------------------------------------------------

module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.10.0' = {
  name: 'deploy-${resolvedName}'
  params: {
    name                     : resolvedName
    location                 : location
    adminUsername            : adminUsername
    adminPassword            : adminPassword
    osType                   : osType
    vmSize                   : vmSize
    imageReference           : imageReference
    zone                     : availabilityZone
    computerName             : resolvedComputerName
    nicConfigurations        : nicConfigurations
    osDisk                   : osDisk
    dataDisks                : resolvedDataDisks
    managedIdentities        : managedIdentities
    bootDiagnostics          : { enabled: enableBootDiagnostics }
    // Windows-specific
    patchMode                     : osType == 'Windows' ? windowsPatchMode : linuxPatchMode
    enableAutomaticUpdates        : osType == 'Windows' ? enableAutomaticUpdates : null
    timeZone                      : osType == 'Windows' && !empty(timeZone) ? timeZone : null
    licenseType                   : osType == 'Windows' && !empty(licenseType) ? licenseType : null
    // Linux-specific
    disablePasswordAuthentication : osType == 'Linux' ? disablePasswordAuthentication : null
    publicKeys                    : osType == 'Linux' ? sshPublicKeys : []
    // Extensions
    extensionMonitoringAgentConfig     : extensionMonitoringAgentConfig
    extensionDependencyAgentConfig     : extensionDependencyAgentConfig
    extensionNetworkWatcherAgentConfig : extensionNetworkWatcherAgentConfig
    extensionAntimalwareConfig         : extensionAntimalwareConfig
    extensionAadJoinConfig             : extensionAadJoinConfig
    // Governance
    diagnosticSettings : diagnosticSettings
    lock               : lockConfig
    roleAssignments    : roleAssignments
    tags               : resolvedTags
    enableTelemetry    : enableTelemetry
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the deployed Virtual Machine.')
output resourceId string = virtualMachine.outputs.resourceId

@description('Name of the deployed Virtual Machine.')
output name string = virtualMachine.outputs.name

@description('Location of the deployed Virtual Machine.')
output location string = virtualMachine.outputs.location

@description('Resource group name the VM was deployed into.')
output resourceGroupName string = virtualMachine.outputs.resourceGroupName

@description('Private IP address of the primary NIC.')
output ipConfigurations array = virtualMachine.outputs.ipConfigurations

@description('System-assigned managed identity principal ID. Empty if not enabled.')
output systemAssignedMIPrincipalId string = virtualMachine.outputs.systemAssignedMIPrincipalId
