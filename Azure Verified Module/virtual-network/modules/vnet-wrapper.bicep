/*
  AVM Wrapper Module: Virtual Network
  ====================================
  Purpose    : Wraps the Azure Verified Module (AVM) for Virtual Network with
               organisation-wide defaults, mandatory tagging, naming conventions,
               and guardrails. Consumers pass only the values that vary per VNet.

  AVM Source : br/public:avm/res/network/virtual-network:0.5.2
  AVM Docs   : https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/virtual-network
*/

metadata name        = 'VNet AVM Wrapper'
metadata description = 'Organisation wrapper around the AVM Virtual Network module.'
metadata owner       = 'Platform / Networking Team'

// ---------------------------------------------------------------------------
// Parameters
// ---------------------------------------------------------------------------

@description('Short environment identifier used in naming and tagging. e.g. prod, nonprod, dev, test.')
@allowed(['prod', 'nonprod', 'dev', 'test', 'staging'])
param environment string

@description('Azure region for the Virtual Network.')
param location string = resourceGroup().location

@description('Override the auto-generated VNet name. Leave empty to use the naming convention: vnet-<workload>-<environment>-<location-short>.')
param nameOverride string = ''

@description('Short name of the workload or project this VNet belongs to. Used in the auto-generated name. e.g. hub, spoke-identity, spoke-prod.')
param workloadName string

@description('Array of IPv4 address prefixes for the Virtual Network address space.')
param addressPrefixes array

@description('Array of subnet definitions. Each item must include name and addressPrefix. All other subnet properties are optional.')
param subnets array = []

@description('Custom DNS server IP addresses. Leave empty to use Azure-provided DNS.')
param dnsServers array = []

@description('Resource ID of a DDoS Protection Plan to associate with the VNet. Leave empty to skip.')
param ddosProtectionPlanResourceId string = ''

@description('Array of VNet peering configurations. Leave empty for no peerings.')
param peerings array = []

@description('Resource ID of a Log Analytics Workspace for diagnostic settings. Leave empty to skip diagnostics.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Retention days for diagnostic logs. Defaults to 30.')
@minValue(7)
@maxValue(365)
param diagnosticRetentionDays int = 30

@description('Apply a resource lock. None = no lock, CanNotDelete = prevent deletion, ReadOnly = prevent changes.')
@allowed(['None', 'CanNotDelete', 'ReadOnly'])
param resourceLock string = 'None'

@description('Array of RBAC role assignments to apply to the VNet resource.')
param roleAssignments array = []

@description('Set false to disable AVM telemetry. Defaults to true.')
param enableTelemetry bool = true

@description('''
Mandatory base tags applied to all resources.
Consumers MUST supply: CostCenter, Owner, and BusinessUnit.
Wrapper merges these with auto-generated Environment and ManagedBy tags.
''')
param mandatoryTags object

@description('Additional arbitrary tags to merge on top of mandatory tags.')
param additionalTags object = {}

// ---------------------------------------------------------------------------
// Variables
// ---------------------------------------------------------------------------

// Abbreviated region map used in the naming convention
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
  : 'vnet-${workloadName}-${environment}-${locationShort}'

var resolvedTags = union(
  {
    Environment : environment
    ManagedBy   : 'Bicep / AVM'
  },
  mandatoryTags,
  additionalTags
)

// Build diagnosticSettings array only when a workspace is provided
var diagnosticSettings = !empty(logAnalyticsWorkspaceResourceId)
  ? [
      {
        name                        : 'diag-${resolvedName}'
        workspaceResourceId         : logAnalyticsWorkspaceResourceId
        metricCategories            : [{ category: 'AllMetrics', retentionPolicy: { days: diagnosticRetentionDays, enabled: true } }]
        logCategoriesAndGroups      : [{ categoryGroup: 'allLogs', retentionPolicy: { days: diagnosticRetentionDays, enabled: true } } ]
      }
    ]
  : []

// Build lock object only when a lock level is requested
var lockConfig = resourceLock != 'None'
  ? { kind: resourceLock, name: 'lock-${resolvedName}' }
  : null

// ---------------------------------------------------------------------------
// AVM Module Call
// ---------------------------------------------------------------------------

module virtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'deploy-${resolvedName}'
  params: {
    name                          : resolvedName
    location                      : location
    addressPrefixes               : addressPrefixes
    subnets                       : subnets
    dnsServers                    : dnsServers
    ddosProtectionPlanResourceId  : !empty(ddosProtectionPlanResourceId) ? ddosProtectionPlanResourceId : null
    peerings                      : peerings
    diagnosticSettings            : diagnosticSettings
    lock                          : lockConfig
    roleAssignments               : roleAssignments
    tags                          : resolvedTags
    enableTelemetry               : enableTelemetry
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the deployed Virtual Network.')
output resourceId string = virtualNetwork.outputs.resourceId

@description('Name of the deployed Virtual Network.')
output name string = virtualNetwork.outputs.name

@description('Location of the deployed Virtual Network.')
output location string = virtualNetwork.outputs.location

@description('Resource group name the Virtual Network was deployed into.')
output resourceGroupName string = virtualNetwork.outputs.resourceGroupName

@description('Array of deployed subnet resource IDs.')
output subnetResourceIds array = virtualNetwork.outputs.subnetResourceIds

@description('Map of subnet name to resource ID.')
output subnetResourceIdMap object = virtualNetwork.outputs.subnetResourceIdMap
