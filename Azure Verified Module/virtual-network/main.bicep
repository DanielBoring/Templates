/*
  Entry Point: Virtual Network Deployment
  ========================================
  Orchestration layer. Calls the vnet-wrapper module and exposes top-level outputs.
  This file is what you target with "az deployment group create".

  Usage:
    az deployment group create \
      --resource-group rg-networking-prod \
      --template-file main.bicep \
      --parameters @parameters/vnet-hub-prod.bicepparam

  Or via the deploy.ps1 helper script (recommended — handles state checks).
*/

targetScope = 'resourceGroup'

// ---------------------------------------------------------------------------
// Parameters  (mirror all wrapper params so .bicepparam files bind here)
// ---------------------------------------------------------------------------

@description('Short environment identifier. e.g. prod, nonprod, dev, test.')
@allowed(['prod', 'nonprod', 'dev', 'test', 'staging'])
param environment string

@description('Azure region. Defaults to the resource group location.')
param location string = resourceGroup().location

@description('Override the auto-generated VNet name. Leave empty to use naming convention.')
param nameOverride string = ''

@description('Short workload name used in naming convention. e.g. hub, spoke-identity.')
param workloadName string

@description('Array of IPv4 address prefixes for the address space.')
param addressPrefixes array

@description('Subnet definitions array. See README for full schema.')
param subnets array = []

@description('Custom DNS server IPs. Empty = Azure DNS.')
param dnsServers array = []

@description('Resource ID of a DDoS Protection Plan. Empty = skip.')
param ddosProtectionPlanResourceId string = ''

@description('VNet peering configurations. Empty = no peerings.')
param peerings array = []

@description('Resource ID of a Log Analytics Workspace for diagnostics. Empty = skip.')
param logAnalyticsWorkspaceResourceId string = ''

@description('Retention days for diagnostic logs.')
@minValue(7)
@maxValue(365)
param diagnosticRetentionDays int = 30

@description('Resource lock level.')
@allowed(['None', 'CanNotDelete', 'ReadOnly'])
param resourceLock string = 'None'

@description('RBAC role assignments for the VNet.')
param roleAssignments array = []

@description('Disable AVM telemetry if required by policy.')
param enableTelemetry bool = true

@description('Mandatory organisational tags. Must include CostCenter, Owner, and BusinessUnit.')
param mandatoryTags object

@description('Optional extra tags merged on top of mandatory tags.')
param additionalTags object = {}

// ---------------------------------------------------------------------------
// Module Call
// ---------------------------------------------------------------------------

module vnet './modules/vnet-wrapper.bicep' = {
  name: 'vnet-deployment'
  params: {
    environment                     : environment
    location                        : location
    nameOverride                    : nameOverride
    workloadName                    : workloadName
    addressPrefixes                 : addressPrefixes
    subnets                         : subnets
    dnsServers                      : dnsServers
    ddosProtectionPlanResourceId    : ddosProtectionPlanResourceId
    peerings                        : peerings
    logAnalyticsWorkspaceResourceId : logAnalyticsWorkspaceResourceId
    diagnosticRetentionDays         : diagnosticRetentionDays
    resourceLock                    : resourceLock
    roleAssignments                 : roleAssignments
    enableTelemetry                 : enableTelemetry
    mandatoryTags                   : mandatoryTags
    additionalTags                  : additionalTags
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Resource ID of the Virtual Network.')
output resourceId string = vnet.outputs.resourceId

@description('Name of the Virtual Network.')
output name string = vnet.outputs.name

@description('Location of the Virtual Network.')
output location string = vnet.outputs.location

@description('Resource group name.')
output resourceGroupName string = vnet.outputs.resourceGroupName

@description('Array of subnet resource IDs.')
output subnetResourceIds array = vnet.outputs.subnetResourceIds

@description('Map of subnet name to resource ID.')
output subnetResourceIdMap object = vnet.outputs.subnetResourceIdMap
