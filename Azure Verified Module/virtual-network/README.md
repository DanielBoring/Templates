# AVM Wrapper — Virtual Network

An organisation-opinionated Bicep wrapper around the [Azure Verified Module (AVM)](https://azure.github.io/Azure-Verified-Modules/) for Virtual Networks. It applies mandatory tagging, a consistent naming convention, and guardrails while keeping the full flexibility of the upstream AVM module.

---

## Table of Contents

1. [What is Azure Verified Modules (AVM)?](#1-what-is-azure-verified-modules-avm)
2. [Why use a wrapper?](#2-why-use-a-wrapper)
3. [Repository structure](#3-repository-structure)
4. [Prerequisites](#4-prerequisites)
5. [How to use this module](#5-how-to-use-this-module)
6. [How to add a new VNet (repeating the pattern)](#6-how-to-add-a-new-vnet-repeating-the-pattern)
7. [Parameter file reference](#7-parameter-file-reference)
8. [Subnet schema](#8-subnet-schema)
9. [Peering schema](#9-peering-schema)
10. [Naming convention](#10-naming-convention)
11. [Tagging strategy](#11-tagging-strategy)
12. [Governance options](#12-governance-options)
13. [Diagnostics](#13-diagnostics)
14. [CI/CD integration](#14-cicd-integration)
15. [Upgrading the AVM module version](#15-upgrading-the-avm-module-version)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. What is Azure Verified Modules (AVM)?

**Azure Verified Modules (AVM)** is Microsoft's official library of production-ready, standardised infrastructure-as-code modules for Bicep and Terraform. Every AVM module is:

| Property | Detail |
|---|---|
| **Owned by Microsoft** | Authored and maintained by Microsoft engineering teams |
| **Tested** | Automated e2e tests run on every release against a real Azure subscription |
| **Versioned** | Semantic versioning — breaking changes only in major versions |
| **Consistent** | All modules follow the same interface patterns: tags, locks, diagnostics, RBAC, telemetry |
| **Discoverable** | Published to the public Bicep registry at `mcr.microsoft.com/bicep/avm/res/…` |

AVM replaces the older Azure Resource Modules (ARM) library and is the recommended module standard going forward.

**Key links:**
- Home page: https://azure.github.io/Azure-Verified-Modules/
- Bicep registry browser: https://github.com/Azure/bicep-registry-modules
- VNet module: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/virtual-network

---

## 2. Why use a wrapper?

The upstream AVM module exposes every parameter Azure supports — over 30 for VNet alone. A wrapper lets your organisation:

- **Enforce defaults** — mandatory tags, lock levels, diagnostic settings without repeating them in every parameter file.
- **Apply a naming convention** — auto-generate `vnet-<workload>-<environment>-<region>` so names are predictable.
- **Reduce cognitive load** — consumers only set the parameters that vary (address space, subnets, workload name). Everything else is handled.
- **Guard against drift** — the `@allowed` decorator on `environment` prevents typos. The `mandatoryTags` object fails the deployment if `CostCenter`, `Owner`, or `BusinessUnit` are missing.
- **Simplify upgrades** — when AVM releases a new version you update `modules/vnet-wrapper.bicep` in one place. All consumers pick it up automatically.

---

## 3. Repository structure

```
virtual-network/
├── main.bicep                          # Entry point — target this file for deployments
├── bicepconfig.json                    # Linting rules + AVM registry alias
├── modules/
│   └── vnet-wrapper.bicep              # Wrapper around AVM — org defaults live here
├── parameters/
│   ├── vnet-hub-prod.bicepparam        # Hub VNet, production
│   ├── vnet-spoke-prod.bicepparam      # Application spoke, production
│   └── vnet-spoke-dev.bicepparam       # Application spoke, development
├── scripts/
│   └── deploy.ps1                      # Repeatable deployment helper
└── README.md                           # This file
```

**Rule of thumb:**
- One `.bicepparam` file per VNet instance.
- `main.bicep` and `modules/vnet-wrapper.bicep` are shared — never edited per-environment.

---

## 4. Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Azure CLI | 2.55+ | https://aka.ms/install-azure-cli |
| Bicep CLI | 0.26+ | `az bicep install` |
| PowerShell | 7.2+ (for deploy.ps1) | https://aka.ms/powershell |
| Contributor or Network Contributor RBAC | On the target resource group | Azure Portal / PIM |

Verify your setup:

```bash
az --version
az bicep version
pwsh --version
```

---

## 5. How to use this module

### 5a. Manual deployment (Azure CLI)

```bash
# 1. Log in
az login

# 2. Set subscription
az account set --subscription "00000000-0000-0000-0000-000000000000"

# 3. Create resource group (if it doesn't exist)
az group create --name rg-networking-prod --location eastus

# 4. What-if preview (always recommended before applying)
az deployment group what-if \
  --resource-group rg-networking-prod \
  --template-file main.bicep \
  --parameters @parameters/vnet-hub-prod.bicepparam

# 5. Deploy
az deployment group create \
  --resource-group rg-networking-prod \
  --template-file main.bicep \
  --parameters @parameters/vnet-hub-prod.bicepparam \
  --name "vnet-hub-prod-$(date +%Y%m%d-%H%M%S)"
```

### 5b. Deployment via the helper script (recommended)

The `scripts/deploy.ps1` helper combines steps 3-5, always runs a what-if, and prints a structured output summary.

```powershell
# Interactive (prompts you to confirm after what-if)
.\scripts\deploy.ps1 `
  -ParameterFile   .\parameters\vnet-hub-prod.bicepparam `
  -ResourceGroupName rg-networking-prod `
  -Location        eastus

# Dry-run only — exits after what-if, no changes made
.\scripts\deploy.ps1 `
  -ParameterFile   .\parameters\vnet-hub-prod.bicepparam `
  -ResourceGroupName rg-networking-prod `
  -Location        eastus `
  -WhatIf

# CI/CD — no interactive prompts, auto-switches subscription
.\scripts\deploy.ps1 `
  -ParameterFile      .\parameters\vnet-spoke-prod.bicepparam `
  -ResourceGroupName  rg-networking-spoke-prod `
  -Location           eastus `
  -SubscriptionId     "00000000-0000-0000-0000-000000000000" `
  -SkipConfirmation
```

---

## 6. How to add a new VNet (repeating the pattern)

Every new Virtual Network gets exactly **one new file** — a `.bicepparam` file. You never touch `main.bicep` or the wrapper.

**Step-by-step:**

1. **Copy the closest existing parameter file** as a starting point.

   ```bash
   cp parameters/vnet-spoke-prod.bicepparam parameters/vnet-spoke-finance-prod.bicepparam
   ```

2. **Edit the new file** — update only the values that differ:
   - `workloadName` — drives the auto-generated name
   - `addressPrefixes` — must not overlap with any existing VNet in your address plan
   - `subnets` — define the subnets your workload needs
   - `mandatoryTags` — update `CostCenter`, `Owner`, and `BusinessUnit`
   - `peerings` — add hub peering if this is a spoke
   - `logAnalyticsWorkspaceResourceId` — point to your workspace

3. **Validate locally** with a what-if:

   ```powershell
   .\scripts\deploy.ps1 `
     -ParameterFile   .\parameters\vnet-spoke-finance-prod.bicepparam `
     -ResourceGroupName rg-networking-spoke-finance-prod `
     -Location        eastus `
     -WhatIf
   ```

4. **Deploy:**

   ```powershell
   .\scripts\deploy.ps1 `
     -ParameterFile   .\parameters\vnet-spoke-finance-prod.bicepparam `
     -ResourceGroupName rg-networking-spoke-finance-prod `
     -Location        eastus
   ```

5. **Commit the new `.bicepparam` file** to source control. The deployment history is then fully auditable.

---

## 7. Parameter file reference

All parameters are defined in `main.bicep`. The table below covers every parameter available to a `.bicepparam` consumer.

### Required

| Parameter | Type | Description |
|---|---|---|
| `environment` | string | `prod`, `nonprod`, `dev`, `test`, or `staging` |
| `workloadName` | string | Short name used in auto-generated VNet name, e.g. `hub`, `spoke-app` |
| `addressPrefixes` | array | One or more CIDR blocks for the VNet address space |
| `mandatoryTags` | object | Must include `CostCenter`, `Owner`, and `BusinessUnit` |

### Optional — commonly set per-VNet

| Parameter | Type | Default | Description |
|---|---|---|---|
| `location` | string | Resource group location | Azure region |
| `nameOverride` | string | `''` | Override auto-generated name. Leave empty to use naming convention |
| `subnets` | array | `[]` | Subnet definitions (see [Subnet schema](#8-subnet-schema)) |
| `dnsServers` | array | `[]` | Custom DNS IPs. Empty = Azure DNS |
| `peerings` | array | `[]` | VNet peering definitions (see [Peering schema](#9-peering-schema)) |
| `logAnalyticsWorkspaceResourceId` | string | `''` | Log Analytics resource ID for diagnostics |
| `additionalTags` | object | `{}` | Extra tags merged on top of mandatory tags |

### Optional — usually set at the environment or team level

| Parameter | Type | Default | Description |
|---|---|---|---|
| `ddosProtectionPlanResourceId` | string | `''` | DDoS Standard plan resource ID |
| `diagnosticRetentionDays` | int | `30` | Log retention in days (7–365) |
| `resourceLock` | string | `'None'` | `None`, `CanNotDelete`, or `ReadOnly` |
| `roleAssignments` | array | `[]` | RBAC assignments on the VNet |
| `enableTelemetry` | bool | `true` | AVM usage telemetry (sent to Microsoft) |

---

## 8. Subnet schema

Each entry in the `subnets` array supports the following properties. Only `name` and `addressPrefix` are required.

```bicep
subnets = [
  {
    name          : 'snet-app'           // Required. Must be unique within the VNet.
    addressPrefix : '10.10.0.0/25'       // Required. Must fall within addressPrefixes.

    // --- Optional governance ---
    networkSecurityGroupResourceId            : '<nsg-resource-id>'
    routeTableResourceId                      : '<udr-resource-id>'
    privateEndpointNetworkPolicies            : 'Disabled'   // 'Disabled' | 'Enabled' | 'NetworkSecurityGroupEnabled' | 'RouteTableEnabled'
    privateLinkServiceNetworkPolicies         : 'Disabled'   // 'Disabled' | 'Enabled'

    // --- Optional service endpoints ---
    serviceEndpoints : [
      { service: 'Microsoft.KeyVault' }
      { service: 'Microsoft.Storage' }
      { service: 'Microsoft.Sql' }
      { service: 'Microsoft.Web' }
    ]

    // --- Optional delegations (e.g. App Service VNet integration) ---
    delegations : [
      {
        name       : 'delegation-appservice'
        properties : { serviceName: 'Microsoft.Web/serverFarms' }
      }
    ]
  }
]
```

**Reserved subnet names** (Azure requires these exact names for specific services):

| Subnet name | Service |
|---|---|
| `AzureFirewallSubnet` | Azure Firewall (min `/26`) |
| `AzureFirewallManagementSubnet` | Azure Firewall forced tunnelling |
| `GatewaySubnet` | VPN / ExpressRoute Gateway (min `/27`) |
| `AzureBastionSubnet` | Azure Bastion (min `/26`) |
| `RouteServerSubnet` | Azure Route Server (min `/27`) |

---

## 9. Peering schema

```bicep
peerings = [
  {
    name                           : 'peer-spoke-to-hub'      // Required. Unique per VNet.
    remoteVirtualNetworkResourceId : '<hub-vnet-resource-id>' // Required.
    allowForwardedTraffic          : true   // Allow traffic forwarded from the remote VNet
    allowGatewayTransit            : false  // Set true on HUB side to share its gateway
    useRemoteGateways              : true   // Set true on SPOKE side to use hub gateway
    allowVirtualNetworkAccess      : true   // Allow traffic between the two VNets
  }
]
```

> **Note:** For hub-spoke topologies, `allowGatewayTransit: true` goes on the **hub** peering, and `useRemoteGateways: true` goes on the **spoke** peering. They are mutually exclusive per-side.

---

## 10. Naming convention

When `nameOverride` is empty the wrapper generates:

```
vnet-<workloadName>-<environment>-<locationShort>
```

| Segment | Example |
|---|---|
| `workloadName = 'hub'` | `vnet-hub-prod-eus` |
| `workloadName = 'spoke-app'` | `vnet-spoke-app-prod-eus` |
| `workloadName = 'spoke-identity'` | `vnet-spoke-identity-dev-eus` |

Location short codes are mapped inside `modules/vnet-wrapper.bicep` (`regionAbbreviations` variable). Add new regions there as required.

---

## 11. Tagging strategy

The wrapper applies a three-layer merge:

```
auto-generated tags   +   mandatoryTags param   +   additionalTags param
       ↑                         ↑                         ↑
  Environment             CostCenter                  Criticality
  ManagedBy               Owner                       DataClass
                          BusinessUnit                Application
```

Later layers win on key collision. `additionalTags` can override `mandatoryTags`, and both can override auto-generated tags if needed.

**Mandatory tags** (deployment fails without these keys in `mandatoryTags`):

| Tag | Purpose |
|---|---|
| `CostCenter` | Finance cost allocation |
| `Owner` | Team or email address responsible for the resource |
| `BusinessUnit` | Division that owns the workload |

These are enforced by Azure Policy in most enterprise landing zones. Aligning the wrapper to the policy prevents deployment failures in governed subscriptions.

---

## 12. Governance options

### Resource locks

```bicep
param resourceLock = 'CanNotDelete'  // Prevents accidental VNet deletion
param resourceLock = 'ReadOnly'      // Prevents all changes (use carefully)
param resourceLock = 'None'          // No lock (suitable for dev/test)
```

Locks are managed by Azure Resource Manager and cannot be bypassed even by Owners unless they first remove the lock.

### RBAC role assignments

```bicep
param roleAssignments = [
  {
    principalId         : '00000000-0000-0000-0000-000000000000'  // Object ID of user/group/SP
    roleDefinitionIdOrName : 'Network Contributor'
    principalType       : 'Group'  // 'User', 'Group', 'ServicePrincipal'
  }
]
```

---

## 13. Diagnostics

When `logAnalyticsWorkspaceResourceId` is set, the wrapper configures a diagnostic setting that sends **all logs and metrics** to the specified workspace. Adjust `diagnosticRetentionDays` per environment:

| Environment | Recommended retention |
|---|---|
| Production | 90 days |
| Non-prod / staging | 30 days |
| Dev / test | 30 days |

To disable diagnostics entirely, leave `logAnalyticsWorkspaceResourceId` as an empty string `''`.

---

## 14. CI/CD integration

### Azure DevOps — pipeline snippet

```yaml
- task: AzureCLI@2
  displayName: 'Deploy VNet: ${{ parameters.vnetName }}'
  inputs:
    azureSubscription: 'sc-azure-prod'
    scriptType: pscore
    scriptLocation: scriptPath
    scriptPath: '$(Build.SourcesDirectory)/Azure Verified Module/virtual-network/scripts/deploy.ps1'
    arguments: >
      -ParameterFile "$(Build.SourcesDirectory)/Azure Verified Module/virtual-network/parameters/$(PARAM_FILE)"
      -ResourceGroupName "$(RESOURCE_GROUP)"
      -Location "$(LOCATION)"
      -SkipConfirmation
```

### GitHub Actions — workflow snippet

```yaml
- name: Deploy VNet
  uses: azure/cli@v2
  with:
    azcliversion: latest
    inlineScript: |
      az deployment group create \
        --resource-group ${{ env.RESOURCE_GROUP }} \
        --template-file "Azure Verified Module/virtual-network/main.bicep" \
        --parameters "Azure Verified Module/virtual-network/parameters/${{ env.PARAM_FILE }}" \
        --name "vnet-${{ github.run_id }}"
```

### Recommended pipeline pattern for multiple VNets

Use a matrix strategy so each VNet has its own deployment job with isolated state:

```yaml
# GitHub Actions example
strategy:
  matrix:
    vnet:
      - { paramFile: vnet-hub-prod.bicepparam,        rg: rg-networking-prod }
      - { paramFile: vnet-spoke-prod.bicepparam,       rg: rg-networking-spoke-prod }
      - { paramFile: vnet-spoke-finance-prod.bicepparam, rg: rg-networking-spoke-finance-prod }
```

---

## 15. Upgrading the AVM module version

1. Check the latest version at: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/network/virtual-network
2. Review the **CHANGELOG** for breaking changes.
3. Update the version pin in `modules/vnet-wrapper.bicep`:
   ```bicep
   // Before
   module virtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
   // After
   module virtualNetwork 'br/public:avm/res/network/virtual-network:0.6.0' = {
   ```
4. Run a what-if against each parameter file before applying:
   ```powershell
   .\scripts\deploy.ps1 -ParameterFile .\parameters\vnet-hub-prod.bicepparam `
     -ResourceGroupName rg-networking-prod -Location eastus -WhatIf
   ```
5. If AVM added new parameters you want to expose, add them to both `modules/vnet-wrapper.bicep` and `main.bicep`.

---

## 16. Troubleshooting

### `BicepCompilationFailedException` — module not found

The AVM module is pulled from the public registry at deployment time. Ensure:
- Outbound HTTPS to `mcr.microsoft.com` is allowed from your deployment agent.
- You are running Bicep CLI 0.26 or later (`az bicep upgrade`).
- `bicepconfig.json` is present in the same directory as `main.bicep`.

### `InvalidTemplateDeployment` — address space overlap

Azure rejects a VNet if its address space overlaps with a peered VNet. Verify your IPAM plan before deploying and use `--what-if` to catch the error before it fails a pipeline.

### `AuthorizationFailed` on diagnostic settings

The deploying identity needs **Monitoring Contributor** or **Log Analytics Contributor** on the Log Analytics Workspace, in addition to **Network Contributor** on the resource group.

### `CanNotDeleteLockExists` when re-running a deployment

A `CanNotDelete` lock does not block updates — only deletions. If a `ReadOnly` lock was applied and you need to modify the VNet, remove the lock first:

```bash
az lock delete \
  --name "lock-vnet-hub-prod-eus" \
  --resource-group rg-networking-prod \
  --resource-name vnet-hub-prod-eus \
  --resource-type Microsoft.Network/virtualNetworks
```

Then redeploy, and re-apply the lock via the parameter file on the next run.

### Telemetry

AVM modules send anonymous usage telemetry to Microsoft by default. To disable this globally, set `enableTelemetry = false` in your parameter files, or remove it from the wrapper's default.
