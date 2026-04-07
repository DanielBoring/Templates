/*
  Parameter File: Spoke VNet — Development
  ==========================================
  Deployment target : rg-networking-spoke-dev (East US)
  VNet name         : vnet-spoke-app-dev-eus  (auto-generated)
  Purpose           : Dev/test spoke. Lighter governance — no lock, shorter log retention.

  Deploy:
    az deployment group create \
      --resource-group rg-networking-spoke-dev \
      --template-file ../main.bicep \
      --parameters @vnet-spoke-dev.bicepparam
*/

using '../main.bicep'

param environment  = 'dev'
param location     = 'eastus'
param workloadName = 'spoke-app'

param addressPrefixes = [
  '10.20.0.0/22'
]

param subnets = [
  {
    name          : 'snet-web'
    addressPrefix : '10.20.0.0/25'
  }
  {
    name          : 'snet-app'
    addressPrefix : '10.20.0.128/25'
  }
  {
    name          : 'snet-data'
    addressPrefix : '10.20.1.0/25'
    privateEndpointNetworkPolicies : 'Disabled'
  }
]

// Dev uses Azure DNS — no custom servers needed
param dnsServers = []

// No peering in dev — isolated environment
param peerings = []

// Shorter retention for dev, diagnostics still enabled for troubleshooting
param logAnalyticsWorkspaceResourceId = '/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-monitoring-dev/providers/Microsoft.OperationalInsights/workspaces/law-platform-dev'
param diagnosticRetentionDays         = 30

// No lock in dev to allow easier cleanup
param resourceLock = 'None'

param mandatoryTags = {
  CostCenter   : 'CC-APP-TEAM-042'
  Owner        : 'app-team@contoso.com'
  BusinessUnit : 'Application Services'
}

param additionalTags = {
  Criticality : 'Low'
  DataClass   : 'Internal'
}
