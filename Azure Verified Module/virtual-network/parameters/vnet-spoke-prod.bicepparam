/*
  Parameter File: Spoke VNet — Production Application
  =====================================================
  Deployment target : rg-networking-spoke-prod (East US)
  VNet name         : vnet-spoke-app-prod-eus  (auto-generated)
  Purpose           : Application workload spoke. Peered back to the hub VNet.

  Deploy:
    az deployment group create \
      --resource-group rg-networking-spoke-prod \
      --template-file ../main.bicep \
      --parameters @vnet-spoke-prod.bicepparam
*/

using '../main.bicep'

// ---------------------------------------------------------------------------
// Identity
// ---------------------------------------------------------------------------
param environment  = 'prod'
param location     = 'eastus'
param workloadName = 'spoke-app'

// ---------------------------------------------------------------------------
// Address Space
// ---------------------------------------------------------------------------
param addressPrefixes = [
  '10.10.0.0/22'
]

// ---------------------------------------------------------------------------
// Subnets
// ---------------------------------------------------------------------------
param subnets = [
  // Web tier
  {
    name          : 'snet-web'
    addressPrefix : '10.10.0.0/25'
    serviceEndpoints : [
      { service: 'Microsoft.Web' }
    ]
  }
  // Application tier
  {
    name          : 'snet-app'
    addressPrefix : '10.10.0.128/25'
    serviceEndpoints : [
      { service: 'Microsoft.KeyVault' }
      { service: 'Microsoft.Storage' }
    ]
  }
  // Data tier
  {
    name          : 'snet-data'
    addressPrefix : '10.10.1.0/25'
    serviceEndpoints : [
      { service: 'Microsoft.Sql' }
      { service: 'Microsoft.Storage' }
    ]
    privateEndpointNetworkPolicies    : 'Disabled'
    privateLinkServiceNetworkPolicies : 'Disabled'
  }
  // App Service VNet integration delegation subnet
  {
    name          : 'snet-appservice-integration'
    addressPrefix : '10.10.1.128/25'
    delegations   : [
      {
        name       : 'delegation-appservice'
        properties : { serviceName: 'Microsoft.Web/serverFarms' }
      }
    ]
  }
]

// ---------------------------------------------------------------------------
// DNS  (point to hub DNS servers / Azure Firewall DNS proxy)
// ---------------------------------------------------------------------------
param dnsServers = [
  '10.0.4.4'   // hub shared services DNS / Firewall DNS proxy
]

// ---------------------------------------------------------------------------
// Hub-Spoke Peering
// ---------------------------------------------------------------------------
// Replace with the actual hub VNet resource ID
param peerings = [
  {
    name                        : 'peer-spoke-app-to-hub'
    remoteVirtualNetworkResourceId : '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-networking-prod/providers/Microsoft.Network/virtualNetworks/vnet-hub-prod-eus'
    allowForwardedTraffic       : true
    allowGatewayTransit         : false
    useRemoteGateways           : true   // use VPN/ER gateway in hub
    allowVirtualNetworkAccess   : true
  }
]

// ---------------------------------------------------------------------------
// Diagnostics
// ---------------------------------------------------------------------------
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
  Criticality  : 'High'
  DataClass    : 'Confidential'
  Application  : 'Order Management System'
}
