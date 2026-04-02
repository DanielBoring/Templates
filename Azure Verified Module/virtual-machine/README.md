# AVM Wrapper — Virtual Machine

An organisation-opinionated Bicep wrapper around the [Azure Verified Module (AVM)](https://azure.github.io/Azure-Verified-Modules/) for Virtual Machines. It applies mandatory tagging, consistent naming, auto-named disks, and sensible extension defaults (Azure Monitor Agent, Network Watcher, Dependency Agent) while exposing a simplified parameter surface to consumers.

---

## Table of Contents

1. [What is Azure Verified Modules (AVM)?](#1-what-is-azure-verified-modules-avm)
2. [Why use a wrapper?](#2-why-use-a-wrapper)
3. [Repository structure](#3-repository-structure)
4. [Prerequisites](#4-prerequisites)
5. [How to use this module](#5-how-to-use-this-module)
6. [How to add a new VM (repeating the pattern)](#6-how-to-add-a-new-vm-repeating-the-pattern)
7. [Handling secrets — adminUsername and adminPassword](#7-handling-secrets--adminusername-and-adminpassword)
8. [Parameter file reference](#8-parameter-file-reference)
9. [Image reference examples](#9-image-reference-examples)
10. [Data disk schema](#10-data-disk-schema)
11. [SSH public key schema (Linux)](#11-ssh-public-key-schema-linux)
12. [Naming convention](#12-naming-convention)
13. [Tagging strategy](#13-tagging-strategy)
14. [Extensions](#14-extensions)
15. [Managed identity](#15-managed-identity)
16. [Governance options](#16-governance-options)
17. [Diagnostics and boot diagnostics](#17-diagnostics-and-boot-diagnostics)
18. [Windows-specific guidance](#18-windows-specific-guidance)
19. [Linux-specific guidance](#19-linux-specific-guidance)
20. [CI/CD integration](#20-cicd-integration)
21. [Upgrading the AVM module version](#21-upgrading-the-avm-module-version)
22. [Troubleshooting](#22-troubleshooting)

---

## 1. What is Azure Verified Modules (AVM)?

**Azure Verified Modules (AVM)** is Microsoft's official library of production-ready, standardised infrastructure-as-code modules for Bicep and Terraform. Every AVM module is:

| Property | Detail |
|---|---|
| **Owned by Microsoft** | Authored and maintained by Microsoft engineering teams |
| **Tested** | Automated end-to-end tests run on every release against a real Azure subscription |
| **Versioned** | Semantic versioning — breaking changes only in major versions |
| **Consistent** | All modules follow the same interface: tags, locks, diagnostics, RBAC, telemetry |
| **Discoverable** | Published to the public Bicep registry at `mcr.microsoft.com/bicep/avm/res/…` |

AVM replaces the older Azure Resource Modules (ARM) library and is the recommended module standard going forward.

**Key links:**
- Home page: https://azure.github.io/Azure-Verified-Modules/
- Bicep registry browser: https://github.com/Azure/bicep-registry-modules
- VM module: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/compute/virtual-machine

---

## 2. Why use a wrapper?

The upstream AVM VM module exposes 60+ parameters. A wrapper lets your organisation:

- **Enforce defaults** — Azure Monitor Agent, Network Watcher, and boot diagnostics are on by default. Consumers opt out deliberately.
- **Apply a naming convention** — auto-generate `vm-<workload>-<env>-<region>-<instance>` with consistent region short codes.
- **Auto-name disks** — OS and data disks are named `<vmname>-osdisk` and `<vmname>-datadisk-01` automatically. No repeated boilerplate.
- **Simplify NIC configuration** — instead of a complex `nicConfigurations` object, consumers provide a subnet resource ID and a handful of flags. The wrapper builds the NIC.
- **Reduce cognitive load** — only set what differs per VM. Everything else is handled or has a safe default.
- **Guard against drift** — `@allowed` on `environment` and `osType` prevents invalid values. `mandatoryTags` fails the deployment if required keys are missing.
- **Centralise upgrades** — when AVM releases a new version, you update one line in `modules/vm-wrapper.bicep`.

---

## 3. Repository structure

```
virtual-machine/
├── main.bicep                          # Entry point — target this file for deployments
├── bicepconfig.json                    # Linting rules + AVM registry alias
├── modules/
│   └── vm-wrapper.bicep                # Wrapper around AVM — org defaults live here
├── parameters/
│   ├── vm-windows-prod.bicepparam      # Windows Server, production
│   ├── vm-linux-prod.bicepparam        # Ubuntu Linux, production (SSH key auth)
│   └── vm-windows-dev.bicepparam       # Windows Server, development (lighter)
├── scripts/
│   └── deploy.ps1                      # Repeatable deployment helper
└── README.md                           # This file
```

**Rule of thumb:**
- One `.bicepparam` file per VM instance.
- `main.bicep` and `modules/vm-wrapper.bicep` are shared — never edited per-VM.

---

## 4. Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Azure CLI | 2.55+ | https://aka.ms/install-azure-cli |
| Bicep CLI | 0.26+ | `az bicep install` |
| PowerShell | 7.2+ (for deploy.ps1) | https://aka.ms/powershell |
| Contributor or Virtual Machine Contributor RBAC | On the target resource group | Azure Portal / PIM |

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

# 3. Set secret environment variables (Windows PowerShell)
$env:VM_ADMIN_USER     = 'azureadmin'
$env:VM_ADMIN_PASSWORD = 'P@ssw0rd!ChangeMe'

# 4. Create resource group (if needed)
az group create --name rg-compute-prod --location eastus

# 5. What-if preview
az deployment group what-if \
  --resource-group rg-compute-prod \
  --template-file main.bicep \
  --parameters @parameters/vm-windows-prod.bicepparam

# 6. Deploy
az deployment group create \
  --resource-group rg-compute-prod \
  --template-file main.bicep \
  --parameters @parameters/vm-windows-prod.bicepparam \
  --name "vm-deploy-$(date +%Y%m%d-%H%M%S)"
```

### 5b. Deployment via the helper script (recommended)

```powershell
# Set secrets first
$env:VM_ADMIN_USER     = 'azureadmin'
$env:VM_ADMIN_PASSWORD = Read-Host 'Enter admin password' -AsSecureString |
                         ConvertFrom-SecureString -AsPlainText

# Interactive (what-if → review → deploy)
.\scripts\deploy.ps1 `
  -ParameterFile   .\parameters\vm-windows-prod.bicepparam `
  -ResourceGroupName rg-compute-prod `
  -Location        eastus

# Dry-run only
.\scripts\deploy.ps1 `
  -ParameterFile   .\parameters\vm-windows-prod.bicepparam `
  -ResourceGroupName rg-compute-prod `
  -Location        eastus `
  -WhatIf

# CI/CD — no prompts, subscription switch
.\scripts\deploy.ps1 `
  -ParameterFile      .\parameters\vm-windows-prod.bicepparam `
  -ResourceGroupName  rg-compute-prod `
  -Location           eastus `
  -SubscriptionId     "00000000-0000-0000-0000-000000000000" `
  -SkipConfirmation
```

---

## 6. How to add a new VM (repeating the pattern)

Every new Virtual Machine gets exactly **one new file** — a `.bicepparam` file.

**Step-by-step:**

1. **Copy the closest existing parameter file:**

   ```bash
   # For a new Windows production VM
   cp parameters/vm-windows-prod.bicepparam parameters/vm-dc-prod.bicepparam

   # For a second instance of an existing VM
   cp parameters/vm-windows-prod.bicepparam parameters/vm-app-prod-02.bicepparam
   ```

2. **Edit the new file** — update only the values that differ:
   - `workloadName` — drives the generated name (`dc`, `sql`, `mgmt`, etc.)
   - `instanceNumber` — `02` if this is a second instance of the same workload
   - `addressPrefix` → `subnetResourceId` — place in the correct subnet
   - `imageReference` — change OS if needed
   - `vmSize` — right-size for the workload
   - `dataDisks` — add disks specific to this VM's role
   - `mandatoryTags` — update `CostCenter`, `Owner`, `BusinessUnit`

3. **Validate:**

   ```powershell
   .\scripts\deploy.ps1 `
     -ParameterFile   .\parameters\vm-dc-prod.bicepparam `
     -ResourceGroupName rg-compute-prod `
     -Location        eastus `
     -WhatIf
   ```

4. **Deploy and commit** the new `.bicepparam` file to source control.

---

## 7. Handling secrets — adminUsername and adminPassword

> **Never hard-code credentials in `.bicepparam` files or commit them to source control.**

### Option 1: Environment variables (recommended for local/pipeline use)

The parameter files use `readEnvironmentVariable()` — a built-in Bicep function that reads a value from the shell environment at deployment time.

```powershell
# Set before deploying
$env:VM_ADMIN_USER     = 'azureadmin'
$env:VM_ADMIN_PASSWORD = 'P@ssw0rd!ChangeMe'
```

In the `.bicepparam` file:
```bicep
param adminUsername = readEnvironmentVariable('VM_ADMIN_USER', 'azureadmin')
param adminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD')
```

### Option 2: Azure Key Vault (recommended for shared pipelines)

Store credentials in Key Vault and reference them at deployment time using the Azure CLI:

```bash
# Retrieve secret and pass directly — never stored in a file
az deployment group create \
  --resource-group rg-compute-prod \
  --template-file main.bicep \
  --parameters @parameters/vm-windows-prod.bicepparam \
  --parameters adminPassword="$(az keyvault secret show \
      --vault-name kv-platform-prod \
      --name vm-admin-password \
      --query value -o tsv)"
```

### Option 3: Azure DevOps / GitHub Actions secrets

In CI/CD pipelines, inject secrets as pipeline variables:

```yaml
# GitHub Actions
- name: Deploy VM
  env:
    VM_ADMIN_USER    : ${{ secrets.VM_ADMIN_USER }}
    VM_ADMIN_PASSWORD: ${{ secrets.VM_ADMIN_PASSWORD }}
  run: |
    az deployment group create ...
```

### Linux SSH-only VMs (no password)

For Linux VMs authenticating via SSH keys, set `disablePasswordAuthentication = true` and leave `adminPassword` unset or empty. No password environment variable is needed.

---

## 8. Parameter file reference

### Required

| Parameter | Type | Description |
|---|---|---|
| `environment` | string | `prod`, `nonprod`, `dev`, `test`, or `staging` |
| `workloadName` | string | Short role name used in naming. e.g. `app`, `dc`, `sql`, `web` |
| `osType` | string | `Windows` or `Linux` |
| `imageReference` | object | OS image. See [Image reference examples](#9-image-reference-examples) |
| `adminUsername` | securestring | Local admin username |
| `subnetResourceId` | string | Resource ID of the subnet for the primary NIC |
| `mandatoryTags` | object | Must include `CostCenter`, `Owner`, and `BusinessUnit` |

### Optional — commonly set per-VM

| Parameter | Type | Default | Description |
|---|---|---|---|
| `location` | string | RG location | Azure region |
| `instanceNumber` | string | `'01'` | Two-digit instance suffix |
| `vmSize` | string | `Standard_D2s_v5` | VM SKU |
| `availabilityZone` | int | `0` | 0 = no zone, 1/2/3 = zone pin |
| `adminPassword` | securestring | `''` | Required for Windows; optional for Linux SSH |
| `disablePasswordAuthentication` | bool | `false` | Linux: set `true` for SSH-only |
| `sshPublicKeys` | array | `[]` | Linux SSH public keys |
| `dataDisks` | array | `[]` | Data disk definitions |
| `osDiskSizeGB` | int | `0` | 0 = image default |
| `osDiskStorageAccountType` | string | `Premium_LRS` | OS disk SKU |
| `logAnalyticsWorkspaceResourceId` | string | `''` | Workspace for diagnostics |
| `mandatoryTags` | object | — | Required organisation tags |
| `additionalTags` | object | `{}` | Extra tags |

### Optional — extensions (all default true except antimalware and Entra join)

| Parameter | Type | Default | Description |
|---|---|---|---|
| `enableAzureMonitorAgent` | bool | `true` | Azure Monitor Agent |
| `enableDependencyAgent` | bool | `true` | VM Insights Dependency Agent |
| `enableNetworkWatcherAgent` | bool | `true` | Network Watcher Agent |
| `enableAntimalware` | bool | `false` | Microsoft Antimalware (Windows) |
| `enableEntraIdJoin` | bool | `false` | Join to Microsoft Entra ID |

### Optional — governance

| Parameter | Type | Default | Description |
|---|---|---|---|
| `resourceLock` | string | `'None'` | `None`, `CanNotDelete`, or `ReadOnly` |
| `roleAssignments` | array | `[]` | RBAC on the VM resource |
| `enableBootDiagnostics` | bool | `true` | Boot diagnostics (managed storage) |
| `diagnosticRetentionDays` | int | `30` | Log retention days |
| `enableTelemetry` | bool | `true` | AVM usage telemetry |

---

## 9. Image reference examples

```bicep
// Windows Server 2022 Datacenter Azure Edition (Gen2, recommended)
param imageReference = {
  publisher : 'MicrosoftWindowsServer'
  offer     : 'WindowsServer'
  sku       : '2022-datacenter-azure-edition'
  version   : 'latest'
}

// Windows Server 2019 Datacenter
param imageReference = {
  publisher : 'MicrosoftWindowsServer'
  offer     : 'WindowsServer'
  sku       : '2019-datacenter-gensecond'
  version   : 'latest'
}

// Ubuntu 22.04 LTS (Jammy) Gen2
param imageReference = {
  publisher : 'Canonical'
  offer     : '0001-com-ubuntu-server-jammy'
  sku       : '22_04-lts-gen2'
  version   : 'latest'
}

// Ubuntu 24.04 LTS (Noble) Gen2
param imageReference = {
  publisher : 'Canonical'
  offer     : 'ubuntu-24_04-lts'
  sku       : 'server-gen2'
  version   : 'latest'
}

// Red Hat Enterprise Linux 9 Gen2
param imageReference = {
  publisher : 'RedHat'
  offer     : 'RHEL'
  sku       : '9-lvm-gen2'
  version   : 'latest'
}

// Rocky Linux 9 Gen2
param imageReference = {
  publisher : 'erockyenterprisesoftwarefoundationinc1653071250513'
  offer     : 'rocky-linux-9'
  sku       : 'rocky-linux-9-gen2'
  version   : 'latest'
}
```

> **Tip:** To list all available images: `az vm image list --all --publisher MicrosoftWindowsServer -o table`

---

## 10. Data disk schema

Each entry in the `dataDisks` array supports:

```bicep
param dataDisks = [
  {
    diskSizeGB          : 256      // Required. Size in GB.
    lun                 : 0        // Optional. Auto-assigned from array index if omitted.
    storageAccountType  : 'Premium_LRS'  // Optional. Defaults to Premium_LRS.
    caching             : 'ReadOnly'     // Optional. Defaults to ReadOnly.
                                         // Use 'None' for database transaction logs.
                                         // Use 'ReadOnly' for data/app disks.
                                         // Use 'ReadWrite' sparingly (only with write-back cache awareness).
  }
  {
    diskSizeGB : 512
    lun        : 1
  }
]
```

The wrapper automatically generates disk names as `<vmname>-datadisk-01`, `<vmname>-datadisk-02`, etc. All disks use `deleteOption: Delete` so they are removed with the VM — change this in the wrapper if your policy requires detaching disks on VM deletion.

**Storage account type guidance:**

| Workload | Recommended SKU |
|---|---|
| Production databases, high IOPS | `Premium_LRS` or `Premium_ZRS` (zone-redundant) |
| General app servers | `StandardSSD_LRS` |
| Dev/test, archival | `Standard_LRS` |
| Latency-sensitive analytics | `UltraSSD_LRS` (requires specific VM SKUs) |

---

## 11. SSH public key schema (Linux)

```bicep
param sshPublicKeys = [
  {
    keyData : 'ssh-rsa AAAAB3NzaC1yc2EAAA...'   // Full public key string
    path    : '/home/azureadmin/.ssh/authorized_keys'
  }
]
```

Generate a key pair locally:
```bash
ssh-keygen -t rsa -b 4096 -C "vm-web-prod" -f ~/.ssh/vm-web-prod
# Public key to include in parameter file: ~/.ssh/vm-web-prod.pub
# Private key to store in Key Vault: ~/.ssh/vm-web-prod
```

Store the private key in Azure Key Vault:
```bash
az keyvault secret set \
  --vault-name kv-platform-prod \
  --name vm-web-prod-ssh-private \
  --file ~/.ssh/vm-web-prod
```

---

## 12. Naming convention

When `nameOverride` is empty the wrapper generates:

```
vm-<workloadName>-<environment>-<locationShort>-<instanceNumber>
```

| Example | Result |
|---|---|
| workload=`app`, env=`prod`, loc=`eastus`, instance=`01` | `vm-app-prod-eus-01` |
| workload=`dc`, env=`prod`, loc=`eastus`, instance=`02` | `vm-dc-prod-eus-02` |
| workload=`sql`, env=`dev`, loc=`australiaeast`, instance=`01` | `vm-sql-dev-aue-01` |

**Windows hostname limit:** Windows computer names are capped at 15 characters. The generated name may exceed this. Use the `computerName` parameter to set a short hostname independently of the resource name:

```bicep
param workloadName   = 'sql-primary'
param instanceNumber = '01'
// Resource name: vm-sql-primary-prod-eus-01  (too long for Windows hostname)
param computerName   = 'SQLPROD01'             // 15 chars max — set this explicitly
```

---

## 13. Tagging strategy

The wrapper applies a three-layer merge:

```
auto-generated tags   +   mandatoryTags param   +   additionalTags param
       ↑                         ↑                         ↑
  Environment             CostCenter                  Criticality
  ManagedBy               Owner                       DataClass
                          BusinessUnit                PatchGroup
                                                      AutoShutdown
```

Later layers win on key collision.

**Mandatory tags** (deployment fails without these keys):

| Tag | Purpose |
|---|---|
| `CostCenter` | Finance cost allocation |
| `Owner` | Team or email address responsible for the resource |
| `BusinessUnit` | Division that owns the workload |

**Recommended additional tags for VMs:**

| Tag | Example values | Purpose |
|---|---|---|
| `PatchGroup` | `Wave1-Sunday-2AM` | Automation runbook patch scheduling |
| `AutoShutdown` | `1900` | Azure Automation / Dev Center shutdown policy |
| `Criticality` | `High`, `Medium`, `Low` | Incident prioritisation |
| `DataClass` | `Confidential`, `Internal` | Information classification |

---

## 14. Extensions

All extensions are pre-wired in the wrapper. Enable or disable each via boolean parameters.

| Extension | Parameter | Default | Notes |
|---|---|---|---|
| Azure Monitor Agent (AMA) | `enableAzureMonitorAgent` | `true` | Replaces MMA/OMS. Required for VM Insights and Sentinel. Requires system-assigned identity. |
| VM Insights Dependency Agent | `enableDependencyAgent` | `true` | Maps network connections. Requires AMA. |
| Network Watcher Agent | `enableNetworkWatcherAgent` | `true` | Required for NSG flow logs, connection monitor, packet capture. |
| Microsoft Antimalware | `enableAntimalware` | `false` | Windows only. Enable on all production Windows VMs. |
| Microsoft Entra ID Join | `enableEntraIdJoin` | `false` | Enables passwordless sign-in and conditional access. Requires Entra P1+. |

> **Note:** AMA requires a [Data Collection Rule (DCR)](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-overview) to be associated with the VM after deployment. Installing AMA here is step 1 — creating and associating the DCR is a separate operation, typically handled by Azure Policy or a separate Bicep module.

---

## 15. Managed identity

The wrapper automatically enables system-assigned managed identity whenever `enableAzureMonitorAgent` is `true` (because AMA uses the identity to authenticate to Azure Monitor). You can also enable it independently:

```bicep
param enableSystemAssignedIdentity = true
```

To attach user-assigned managed identities:

```bicep
param userAssignedIdentityResourceIds = [
  '/subscriptions/.../resourceGroups/rg-identity/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-app-prod'
]
```

The system-assigned identity principal ID is available as an output (`systemAssignedMIPrincipalId`) for use in downstream RBAC assignments.

---

## 16. Governance options

### Resource locks

```bicep
param resourceLock = 'CanNotDelete'  // Production VMs — prevent accidental deletion
param resourceLock = 'None'          // Dev/test — allow easy cleanup
```

### RBAC role assignments

```bicep
param roleAssignments = [
  {
    principalId            : '00000000-0000-0000-0000-000000000000'
    roleDefinitionIdOrName : 'Virtual Machine Contributor'
    principalType          : 'Group'
  }
  {
    principalId            : '00000000-0000-0000-0000-000000000000'
    roleDefinitionIdOrName : 'Virtual Machine User Login'   // Entra ID sign-in
    principalType          : 'Group'
  }
]
```

---

## 17. Diagnostics and boot diagnostics

### Boot diagnostics

Enabled by default with Azure-managed storage (no storage account required):

```bicep
param enableBootDiagnostics = true   // Default — captures screenshot and serial log
```

Access boot diagnostics in the Azure portal under the VM → Support + Troubleshooting → Boot diagnostics.

### Azure Monitor diagnostic settings

When `logAnalyticsWorkspaceResourceId` is set, the wrapper sends VM metrics to the workspace:

```bicep
param logAnalyticsWorkspaceResourceId = '/subscriptions/.../workspaces/law-platform-prod'
param diagnosticRetentionDays         = 90   // Production
```

> **Note:** VM-level guest OS metrics and logs (CPU, memory, disk, event logs) require the Azure Monitor Agent extension and a Data Collection Rule — the `diagnosticSettings` parameter here covers only the ARM resource-level metrics (host-level VM metrics).

---

## 18. Windows-specific guidance

### Patch management

| Mode | When to use |
|---|---|
| `AutomaticByPlatform` | **Recommended for production.** Azure manages patch orchestration via Update Manager. Supports maintenance windows and pre/post scripts. |
| `AutomaticByOS` | Windows Update manages patches on the OS. Less control — not recommended for fleets. |
| `Manual` | You manage patches fully (WSUS, MECM, etc.). |

### Azure Hybrid Benefit

If you hold Software Assurance-covered Windows Server licences, set:

```bicep
param licenseType = 'Windows_Server'
```

This saves approximately 40% on Windows VM compute costs. Applies per-VM and is always recommended if your organisation is SA-licensed.

### Time zone

Set the correct time zone to ensure scheduled tasks and event log timestamps are accurate:

```bicep
param timeZone = 'AUS Eastern Standard Time'    // Sydney
param timeZone = 'Eastern Standard Time'         // New York
param timeZone = 'GMT Standard Time'             // London (non-DST)
param timeZone = 'UTC'                           // UTC (recommended for servers)
```

Full list: `tzutil /l` on any Windows machine or https://aka.ms/timezone-ids

---

## 19. Linux-specific guidance

### SSH key authentication (recommended)

```bicep
param disablePasswordAuthentication = true
param adminPassword                 = ''    // Leave empty
param sshPublicKeys = [
  {
    keyData : 'ssh-rsa AAAAB3Nz...'
    path    : '/home/azureadmin/.ssh/authorized_keys'
  }
]
```

### Patch management

```bicep
param linuxPatchMode = 'AutomaticByPlatform'  // Recommended — Azure Update Manager
param linuxPatchMode = 'ImageDefault'          // Use the image's default update mechanism
```

### Microsoft Entra ID join for Linux

The `enableEntraIdJoin` extension for Linux VMs requires:
1. The VM must be in a subscription with Microsoft Entra ID P1 licensing.
2. The VM needs outbound HTTPS to `login.microsoftonline.com` and `pas.windows.net`.
3. Users sign in with `username@domain.com` (UPN).
4. Conditional Access policies apply to the VM access.

---

## 20. CI/CD integration

### Azure DevOps — pipeline snippet

```yaml
- task: AzureCLI@2
  displayName: 'Deploy VM: ${{ parameters.paramFile }}'
  env:
    VM_ADMIN_USER    : $(vmAdminUser)       # Pipeline variable (secret)
    VM_ADMIN_PASSWORD: $(vmAdminPassword)   # Pipeline variable (secret)
  inputs:
    azureSubscription : 'sc-azure-prod'
    scriptType        : pscore
    scriptLocation    : scriptPath
    scriptPath        : '$(Build.SourcesDirectory)/Azure Verified Module/virtual-machine/scripts/deploy.ps1'
    arguments         : >
      -ParameterFile "$(Build.SourcesDirectory)/Azure Verified Module/virtual-machine/parameters/$(PARAM_FILE)"
      -ResourceGroupName "$(RESOURCE_GROUP)"
      -Location "$(LOCATION)"
      -SkipConfirmation
```

### GitHub Actions — workflow snippet

```yaml
- name: Deploy VM
  env:
    VM_ADMIN_USER    : ${{ secrets.VM_ADMIN_USER }}
    VM_ADMIN_PASSWORD: ${{ secrets.VM_ADMIN_PASSWORD }}
  uses: azure/cli@v2
  with:
    azcliversion: latest
    inlineScript: |
      az deployment group create \
        --resource-group ${{ env.RESOURCE_GROUP }} \
        --template-file "Azure Verified Module/virtual-machine/main.bicep" \
        --parameters "Azure Verified Module/virtual-machine/parameters/${{ env.PARAM_FILE }}" \
        --name "vm-${{ github.run_id }}"
```

### Matrix strategy for multiple VMs

```yaml
strategy:
  matrix:
    vm:
      - { paramFile: vm-app-prod-01.bicepparam,  rg: rg-compute-prod }
      - { paramFile: vm-app-prod-02.bicepparam,  rg: rg-compute-prod }
      - { paramFile: vm-dc-prod-01.bicepparam,   rg: rg-identity-prod }
      - { paramFile: vm-sql-prod-01.bicepparam,  rg: rg-data-prod }
```

---

## 21. Upgrading the AVM module version

1. Check the latest release: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/compute/virtual-machine
2. Review the **CHANGELOG** for breaking changes (especially around `nicConfigurations`, extension objects, or managed identity structure).
3. Update the version pin in `modules/vm-wrapper.bicep`:
   ```bicep
   // Before
   module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.10.0' = {
   // After
   module virtualMachine 'br/public:avm/res/compute/virtual-machine:0.11.0' = {
   ```
4. Run what-if against each parameter file before applying:
   ```powershell
   .\scripts\deploy.ps1 -ParameterFile .\parameters\vm-windows-prod.bicepparam `
     -ResourceGroupName rg-compute-prod -Location eastus -WhatIf
   ```
5. If the new AVM version adds parameters you want to expose, add them to both `modules/vm-wrapper.bicep` and `main.bicep`.

---

## 22. Troubleshooting

### `BicepCompilationFailedException` — module not found

The AVM module is pulled from the public registry at deployment time.
- Ensure outbound HTTPS to `mcr.microsoft.com` is allowed from your deployment agent.
- Run `az bicep upgrade` to get the latest Bicep CLI.
- Confirm `bicepconfig.json` is in the same directory as `main.bicep`.

### `readEnvironmentVariable: variable not found`

The `adminPassword` environment variable is not set. Before deploying:
```powershell
$env:VM_ADMIN_PASSWORD = Read-Host 'Password' -AsSecureString | ConvertFrom-SecureString -AsPlainText
```

### `OperationNotAllowed` — VM SKU not available in zone

Not all VM SKUs are available in all zones. Check availability:
```bash
az vm list-skus --location eastus --zone --output table | grep Standard_D2s_v5
```
Either choose a different zone or a different SKU.

### `AuthorizationFailed` on extension deployment

The deploying identity needs **Virtual Machine Contributor** at minimum. For extensions that write to Log Analytics, it also needs **Monitoring Contributor** on the workspace resource group.

### `CanNotDeleteLockExists` when redeploying

A `CanNotDelete` lock does not block updates — only deletions. If you applied a `ReadOnly` lock, remove it first:
```bash
az lock delete \
  --name "lock-vm-app-prod-eus-01" \
  --resource-group rg-compute-prod \
  --resource-name vm-app-prod-eus-01 \
  --resource-type Microsoft.Compute/virtualMachines
```

### Windows hostname too long

Windows computer names must be 15 characters or fewer. If the auto-generated VM name is longer, set `computerName` explicitly:
```bicep
param computerName = 'APPPROD01'   // 15 chars max
```

### Extension conflicts with existing VM

If redeploying a VM that already has an extension installed under a different method (e.g., MMA/OMS agent), remove the old extension first:
```bash
az vm extension delete \
  --resource-group rg-compute-prod \
  --vm-name vm-app-prod-eus-01 \
  --name MicrosoftMonitoringAgent
```

### Telemetry

AVM modules send anonymous usage telemetry to Microsoft by default. To disable:
```bicep
param enableTelemetry = false
```
