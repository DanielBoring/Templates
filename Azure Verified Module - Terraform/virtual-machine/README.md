# AVM Wrapper — Virtual Machine (Terraform)

An organisation-opinionated Terraform wrapper around the [Azure Verified Module (AVM)](https://azure.github.io/Azure-Verified-Modules/) for Virtual Machines. It applies mandatory tagging, a consistent naming convention, auto-named disks, sensible extension defaults (Azure Monitor Agent, Network Watcher, Dependency Agent), and a simplified parameter surface so consumers only set what differs per VM.

**TL;DR — key differences from using AVM directly:**
- **Simplified NIC** — provide a subnet resource ID; the wrapper builds the full `network_interfaces` map.
- **Auto-named disks** — OS disk: `<vmname>-osdisk`; data disks: `<vmname>-datadisk-01`, `<vmname>-datadisk-02`.
- **Three-layer tag merge** — auto-generated + mandatory (CostCenter/Owner/BusinessUnit) + additional.
- **Extension booleans** — AMA, Dependency Agent, and Network Watcher default to `true`. Toggle with single variables.
- **OS branching** — Windows and Linux parameters are handled internally; the same wrapper covers both.

**Step-by-step deployment guide:** [RUNBOOK.md](RUNBOOK.md)

---

## Table of Contents

1. [Repository structure](#1-repository-structure)
2. [Prerequisites](#2-prerequisites)
3. [How to use this module](#3-how-to-use-this-module)
4. [Adding a new VM](#4-adding-a-new-vm)
5. [Managing secrets](#5-managing-secrets)
6. [Variable reference](#6-variable-reference)
7. [Image reference examples](#7-image-reference-examples)
8. [Data disk schema](#8-data-disk-schema)
9. [SSH public key schema (Linux)](#9-ssh-public-key-schema-linux)
10. [Naming convention](#10-naming-convention)
11. [Tagging strategy](#11-tagging-strategy)
12. [Extensions](#12-extensions)
13. [Managed identity](#13-managed-identity)
14. [Governance options](#14-governance-options)
15. [Diagnostics and boot diagnostics](#15-diagnostics-and-boot-diagnostics)
16. [Windows-specific guidance](#16-windows-specific-guidance)
17. [Linux-specific guidance](#17-linux-specific-guidance)
18. [CI/CD integration](#18-cicd-integration)
19. [Upgrading the AVM module version](#19-upgrading-the-avm-module-version)
20. [Troubleshooting](#20-troubleshooting)

---

## 1. Repository structure

```
virtual-machine/
├── providers.tf                        # Terraform + AzureRM provider requirements
├── main.tf                             # Root module — passes vars to wrapper
├── variables.tf                        # Root module variable declarations
├── outputs.tf                          # Root module outputs
├── terraform.tfvars.example            # Copy to terraform.tfvars for manual use
├── modules/
│   └── vm-wrapper/
│       ├── main.tf                     # Wrapper — calls AVM, enforces org defaults
│       ├── variables.tf                # Wrapper input variables
│       └── outputs.tf                  # Wrapper outputs
├── environments/
│   ├── vm-windows-dev.tfvars.example   # Windows Server, development (template — copy to .tfvars)
│   └── vm-linux-dev.tfvars.example     # Ubuntu Linux, development (template — copy to .tfvars)
├── scripts/
│   └── deploy.ps1                      # Repeatable deployment helper
└── RUNBOOK.md                          # Step-by-step lab guide
```

**Rule of thumb:**
- One `.tfvars` file per VM instance in `environments/`.
- `main.tf`, `variables.tf`, and `modules/vm-wrapper/` are shared — never edited per-VM.
- `providers.tf` is edited only to update provider or Terraform version constraints.

---

## 2. Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Terraform | 1.9+ | https://developer.hashicorp.com/terraform/install |
| Azure CLI | 2.55+ | https://aka.ms/install-azure-cli |
| PowerShell | 7.2+ (for deploy.ps1) | https://aka.ms/powershell |
| Contributor or Virtual Machine Contributor RBAC | On the target resource group | Azure Portal / PIM |

Verify your setup:

```powershell
terraform version
az --version
pwsh --version
```

Authenticate:

```powershell
az login
az account set --subscription "00000000-0000-0000-0000-000000000000"
```

---

## 3. How to use this module

### 3a. Using the deploy script (recommended)

```powershell
# 1. Set secrets as environment variables
$env:TF_VAR_admin_username = 'azureadmin'
$env:TF_VAR_admin_password = Read-Host 'Password' -AsSecureString |
                              ConvertFrom-SecureString -AsPlainText

# 2. Dry-run (plan only — no changes made)
.\scripts\deploy.ps1 -VarFile environments/vm-windows-dev.tfvars -WhatIf

# 3. Deploy interactively (prompts for confirmation)
.\scripts\deploy.ps1 -VarFile environments/vm-windows-dev.tfvars

# 4. CI/CD — no prompts, explicit subscription
.\scripts\deploy.ps1 `
  -VarFile          environments/vm-windows-dev.tfvars `
  -SubscriptionId   "00000000-0000-0000-0000-000000000000" `
  -SkipConfirmation

# 5. Destroy
.\scripts\deploy.ps1 -VarFile environments/vm-windows-dev.tfvars -Destroy
```

### 3b. Manual Terraform commands

```bash
# Set secrets
export TF_VAR_admin_username='azureadmin'
export TF_VAR_admin_password='P@ssw0rd!ChangeMe'

# Initialise — downloads AVM from the registry
terraform init

# Plan — preview changes
terraform plan -var-file="environments/vm-windows-dev.tfvars"

# Apply
terraform apply -var-file="environments/vm-windows-dev.tfvars"

# Destroy
terraform destroy -var-file="environments/vm-windows-dev.tfvars"
```

---

## 4. Adding a new VM

Every new Virtual Machine is exactly **one new `.tfvars` file** in `environments/`.

```powershell
# Copy the closest existing template (.example stays in git; .tfvars is gitignored)
Copy-Item environments/vm-windows-dev.tfvars.example environments/vm-sql-prod.tfvars

# Edit — change only values that differ:
# - workload_name   (drives the name: vm-<workload>-<env>-<region>-<instance>)
# - environment     (dev, staging, prod, etc.)
# - vm_size         (right-size for the workload)
# - subnet_id       (correct subnet for this VM)
# - instance_number (02 if this is a second instance)
# - source_image_reference (different OS if needed)
# - data_disks      (role-specific disks)
# - mandatory_tags  (CostCenter, Owner, BusinessUnit for this workload)
```

Validate before deploying:

```powershell
.\scripts\deploy.ps1 -VarFile environments/vm-sql-prod.tfvars -WhatIf
```

Commit the new `.tfvars` file to source control. The `modules/` and root module files are unchanged.

> **Note on Terraform state:** Each VM instance should have its own state file in remote state. Use a separate `-backend-config` or workspace per instance to keep state isolated.

---

## 5. Managing secrets

> **Never hard-code credentials in `.tfvars` files or commit them to source control.**

### Option 1: Environment variables (recommended for local and pipeline use)

Terraform reads `TF_VAR_<variable_name>` environment variables automatically:

```powershell
# PowerShell
$env:TF_VAR_admin_username = 'azureadmin'
$env:TF_VAR_admin_password = Read-Host 'Password' -AsSecureString |
                              ConvertFrom-SecureString -AsPlainText

# Bash / Linux / macOS
export TF_VAR_admin_username='azureadmin'
export TF_VAR_admin_password='P@ssw0rd!ChangeMe'
```

### Option 2: Azure Key Vault + Terraform data source

```hcl
data "azurerm_key_vault_secret" "admin_password" {
  name         = "vm-admin-password"
  key_vault_id = data.azurerm_key_vault.platform.id
}

module "vm" {
  # ...
  admin_password = data.azurerm_key_vault_secret.admin_password.value
}
```

### Option 3: CI/CD pipeline secrets

**GitHub Actions:**
```yaml
env:
  TF_VAR_admin_username: ${{ secrets.VM_ADMIN_USERNAME }}
  TF_VAR_admin_password: ${{ secrets.VM_ADMIN_PASSWORD }}
```

**Azure DevOps:**
```yaml
env:
  TF_VAR_admin_username: $(vmAdminUsername)   # Pipeline variable (secret)
  TF_VAR_admin_password: $(vmAdminPassword)
```

### Linux SSH-only VMs

For Linux VMs using SSH key authentication, set `disable_password_authentication = true` and leave `admin_password` unset. No password environment variable is needed.

---

## 6. Variable reference

### Required

| Variable | Type | Description |
|---|---|---|
| `subscription_id` | string | Azure subscription ID |
| `resource_group_name` | string | Existing resource group name |
| `workload_name` | string | Short role name used in naming. e.g. `app`, `dc`, `sql`, `web` |
| `environment` | string | `prod`, `nonprod`, `dev`, `test`, or `staging` |
| `location` | string | Azure region. e.g. `eastus`, `australiaeast` |
| `os_type` | string | `Windows` or `Linux` |
| `source_image_reference` | object | OS image — see [Image reference examples](#7-image-reference-examples) |
| `admin_username` | string (sensitive) | Local admin username |
| `subnet_id` | string | Resource ID of the subnet for the primary NIC |
| `mandatory_tags` | object | Must include `CostCenter`, `Owner`, `BusinessUnit` |

### Optional — commonly set per-VM

| Variable | Type | Default | Description |
|---|---|---|---|
| `instance_number` | string | `"01"` | Two-digit instance suffix |
| `vm_size` | string | `Standard_D2s_v5` | VM SKU |
| `availability_zone` | string | `null` | `"1"`, `"2"`, `"3"`, or `null` |
| `admin_password` | string (sensitive) | `""` | Required for Windows; optional for Linux SSH |
| `os_disk_size_gb` | number | `0` | 0 = image default |
| `os_disk_storage_account_type` | string | `Premium_LRS` | OS disk SKU |
| `data_disks` | list(object) | `[]` | Data disk definitions |
| `log_analytics_workspace_id` | string | `""` | Workspace for diagnostic settings |
| `additional_tags` | map(string) | `{}` | Extra tags |

### Optional — extensions (all default true except antimalware and Entra join)

| Variable | Default | Description |
|---|---|---|
| `enable_azure_monitor_agent` | `true` | Azure Monitor Agent |
| `enable_dependency_agent` | `true` | VM Insights Dependency Agent |
| `enable_network_watcher_agent` | `true` | Network Watcher Agent |
| `enable_antimalware` | `false` | Microsoft Antimalware (Windows only) |
| `enable_entra_id_join` | `false` | Microsoft Entra ID join |

### Optional — governance

| Variable | Default | Description |
|---|---|---|
| `resource_lock` | `"None"` | `"None"`, `"CanNotDelete"`, or `"ReadOnly"` |
| `enable_boot_diagnostics` | `true` | Boot diagnostics with managed storage |
| `enable_telemetry` | `true` | AVM anonymous usage telemetry |
| `name_override` | `""` | Override auto-generated VM name |

---

## 7. Image reference examples

```hcl
# Windows Server 2022 Datacenter Azure Edition (Gen2, recommended)
source_image_reference = {
  publisher = "MicrosoftWindowsServer"
  offer     = "WindowsServer"
  sku       = "2022-datacenter-azure-edition"
  version   = "latest"
}

# Windows Server 2019 Datacenter
source_image_reference = {
  publisher = "MicrosoftWindowsServer"
  offer     = "WindowsServer"
  sku       = "2019-datacenter-gensecond"
  version   = "latest"
}

# Ubuntu 22.04 LTS (Jammy) Gen2
source_image_reference = {
  publisher = "Canonical"
  offer     = "0001-com-ubuntu-server-jammy"
  sku       = "22_04-lts-gen2"
  version   = "latest"
}

# Ubuntu 24.04 LTS (Noble) Gen2
source_image_reference = {
  publisher = "Canonical"
  offer     = "ubuntu-24_04-lts"
  sku       = "server-gen2"
  version   = "latest"
}

# Red Hat Enterprise Linux 9
source_image_reference = {
  publisher = "RedHat"
  offer     = "RHEL"
  sku       = "9-lvm-gen2"
  version   = "latest"
}
```

> List available images: `az vm image list --all --publisher MicrosoftWindowsServer -o table`

---

## 8. Data disk schema

```hcl
data_disks = [
  {
    disk_size_gb         = 256       # Required. Size in GB.
    lun                  = 0         # Optional. Auto-assigned from index if omitted.
    storage_account_type = "Premium_LRS"  # Optional. Default: Premium_LRS.
    caching              = "ReadOnly"     # Optional. Default: ReadOnly.
                                          # ReadOnly  — app/data disks
                                          # None      — database transaction logs
                                          # ReadWrite — use sparingly
  },
  {
    disk_size_gb = 512
    lun          = 1
  }
]
```

The wrapper auto-names disks: `<vmname>-datadisk-01`, `<vmname>-datadisk-02`, etc.

---

## 9. SSH public key schema (Linux)

```hcl
disable_password_authentication = true

ssh_public_keys = [
  {
    username   = "azureadmin"            # Must match admin_username
    public_key = "ssh-rsa AAAAB3Nz..."  # Full public key string
  }
]
```

Generate a key pair:

```bash
ssh-keygen -t rsa -b 4096 -C "vm-app-dev" -f ~/.ssh/vm-app-dev
# Public key (include in .tfvars): ~/.ssh/vm-app-dev.pub
# Private key (store in Key Vault): ~/.ssh/vm-app-dev
```

---

## 10. Naming convention

When `name_override` is empty, the wrapper generates:

```
vm-<workload_name>-<environment>-<location_short>-<instance_number>
```

| Example inputs | Generated name |
|---|---|
| workload=`app`, env=`prod`, loc=`eastus`, instance=`01` | `vm-app-prod-eus-01` |
| workload=`dc`, env=`prod`, loc=`eastus`, instance=`02` | `vm-dc-prod-eus-02` |
| workload=`sql`, env=`dev`, loc=`australiaeast`, instance=`01` | `vm-sql-dev-aue-01` |

**Windows hostname limit:** Windows computer names are capped at 15 characters. If the auto-generated name is longer, set `computer_name` explicitly:

```hcl
workload_name = "sql-primary"   # Generates: vm-sql-primary-prod-eus-01 (too long)
computer_name = "SQLPROD01"     # 15 chars max
```

---

## 11. Tagging strategy

The wrapper applies a three-layer merge:

```
auto-generated tags   +   mandatory_tags variable   +   additional_tags variable
       ↑                         ↑                             ↑
  Environment             CostCenter                      Criticality
  ManagedBy               Owner                           DataClass
                          BusinessUnit                    PatchGroup
                                                          AutoShutdown
```

Later layers win on key collision. `mandatory_tags` replaces auto-generated tags of the same key.

**Mandatory tags** (deployment fails `validation {}` without all three keys):

| Tag | Purpose |
|---|---|
| `CostCenter` | Finance cost allocation |
| `Owner` | Team or email responsible for the resource |
| `BusinessUnit` | Division that owns the workload |

---

## 12. Extensions

| Extension | Variable | Default | Notes |
|---|---|---|---|
| Azure Monitor Agent | `enable_azure_monitor_agent` | `true` | Replaces MMA/OMS. Required for VM Insights, Sentinel, Update Manager. Automatically enables system-assigned identity. |
| VM Insights Dependency Agent | `enable_dependency_agent` | `true` | Maps network connections. Requires AMA. |
| Network Watcher Agent | `enable_network_watcher_agent` | `true` | Required for NSG flow logs, connection monitor, packet capture. |
| Microsoft Antimalware | `enable_antimalware` | `false` | Windows only. Enable on all production Windows VMs. |
| Microsoft Entra ID Join | `enable_entra_id_join` | `false` | Passwordless sign-in and Conditional Access. Requires Entra P1. |

> **AMA + DCR:** Installing AMA is step 1. To collect guest OS data (CPU, memory, event logs), you must also create and associate a **Data Collection Rule (DCR)**. That is handled separately by Azure Policy or a dedicated Terraform module.

---

## 13. Managed identity

The wrapper automatically enables system-assigned managed identity when `enable_azure_monitor_agent = true` (AMA authenticates to Azure Monitor via the identity).

The principal ID is available as an output for downstream RBAC assignments:

```hcl
# Grant VM identity access to a Key Vault
resource "azurerm_role_assignment" "vm_kv_secrets" {
  scope                = azurerm_key_vault.example.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.vm.system_assigned_identity_principal_id
}
```

---

## 14. Governance options

### Resource locks

```hcl
resource_lock = "CanNotDelete"  # Production VMs — prevents accidental deletion
resource_lock = "None"          # Dev/test — allow easy cleanup
```

A `CanNotDelete` lock does not block updates or redeployments — only `DELETE` operations.

### RBAC role assignments

RBAC assignments are passed directly to the AVM module. Add them to a local in `main.tf` or expose them as a variable if teams need to assign access:

```hcl
# In modules/vm-wrapper/main.tf, add to the AVM module call:
role_assignments = {
  vm_contributor = {
    principal_id            = "00000000-0000-0000-0000-000000000000"
    role_definition_id_or_name = "Virtual Machine Contributor"
    principal_type          = "Group"
  }
}
```

---

## 15. Diagnostics and boot diagnostics

### Boot diagnostics

Enabled by default (Azure-managed storage — no storage account needed):

```hcl
enable_boot_diagnostics = true   # Default — captures screenshot + serial log
```

### Azure Monitor diagnostic settings

When `log_analytics_workspace_id` is set, the wrapper configures diagnostic settings to send VM host-level metrics to that workspace:

```hcl
log_analytics_workspace_id = "/subscriptions/.../workspaces/law-platform-prod"
```

> Guest OS metrics and logs (CPU %, memory, disk, event logs) require AMA + a Data Collection Rule — this is separate from the diagnostic settings here, which cover ARM resource-level metrics only.

---

## 16. Windows-specific guidance

### Patch mode

| Mode | Recommended when |
|---|---|
| `AutomaticByPlatform` | Production — Azure Update Manager with maintenance windows |
| `AutomaticByOS` | Simple VMs — Windows Update manages patches on the OS |
| `Manual` | WSUS/MECM-managed environments |

### Azure Hybrid Benefit

Save ~40% on Windows Server compute costs with Software Assurance licences:

```hcl
license_type = "Windows_Server"
```

### Time zone

```hcl
time_zone = "UTC"                          # Recommended for servers
time_zone = "Eastern Standard Time"        # US Eastern
time_zone = "AUS Eastern Standard Time"    # Sydney
time_zone = "GMT Standard Time"            # London (non-DST)
```

---

## 17. Linux-specific guidance

### SSH key authentication (recommended)

```hcl
disable_password_authentication = true
admin_password                  = ""   # Not required

ssh_public_keys = [
  {
    username   = "azureadmin"
    public_key = "ssh-rsa AAAAB3Nz..."
  }
]
```

### Patch mode

```hcl
linux_patch_mode = "AutomaticByPlatform"  # Azure Update Manager (recommended)
linux_patch_mode = "ImageDefault"          # Image's built-in update mechanism
```

---

## 18. CI/CD integration

### GitHub Actions

```yaml
name: Deploy VM

on:
  workflow_dispatch:
    inputs:
      var_file:
        description: 'Var file to deploy'
        required: true
        default: 'environments/vm-windows-dev.tfvars'

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: "~1.9"

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id:       ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id:       ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Terraform Init
        run: terraform init
        working-directory: Azure Verified Module - Terraform/virtual-machine

      - name: Terraform Plan
        env:
          TF_VAR_admin_username: ${{ secrets.VM_ADMIN_USERNAME }}
          TF_VAR_admin_password: ${{ secrets.VM_ADMIN_PASSWORD }}
        run: |
          terraform plan \
            -var-file="${{ inputs.var_file }}" \
            -out=tfplan.out
        working-directory: Azure Verified Module - Terraform/virtual-machine

      - name: Terraform Apply
        env:
          TF_VAR_admin_username: ${{ secrets.VM_ADMIN_USERNAME }}
          TF_VAR_admin_password: ${{ secrets.VM_ADMIN_PASSWORD }}
        run: terraform apply tfplan.out
        working-directory: Azure Verified Module - Terraform/virtual-machine
```

### Matrix strategy for multiple VMs

```yaml
strategy:
  matrix:
    vm:
      - { varFile: vm-app-prod-01.tfvars,  stateKey: vm-app-prod-01.tfstate }
      - { varFile: vm-app-prod-02.tfvars,  stateKey: vm-app-prod-02.tfstate }
      - { varFile: vm-dc-prod-01.tfvars,   stateKey: vm-dc-prod-01.tfstate }
```

---

## 19. Upgrading the AVM module version

1. Check the latest release: https://github.com/Azure/terraform-azurerm-avm-res-compute-virtualmachine/releases
2. Review the **CHANGELOG** for breaking changes (especially `network_interfaces`, extension object schemas, or managed identity structure).
3. Update the version pin in `modules/vm-wrapper/main.tf`:

   ```hcl
   # Before
   source  = "Azure/avm-res-compute-virtualmachine/azurerm"
   version = "~> 0.17"

   # After
   source  = "Azure/avm-res-compute-virtualmachine/azurerm"
   version = "~> 0.18"
   ```

4. Run `terraform init -upgrade` to download the new version.
5. Run a plan against each environment var file before applying:

   ```powershell
   .\scripts\deploy.ps1 -VarFile environments/vm-windows-dev.tfvars -WhatIf
   ```

6. Apply to dev → staging → prod in sequence.

---

## 20. Troubleshooting

### `Error: Module not found` on init

The AVM module is downloaded from the Terraform Registry during `terraform init`.
- Ensure outbound HTTPS to `registry.terraform.io` is allowed from your machine or pipeline agent.
- Run `terraform init -upgrade` to force a fresh download.
- Confirm `providers.tf` specifies `required_version = ">= 1.9"`.

### `Variable not supplied: admin_password`

The `admin_password` environment variable is not set. Set it before running Terraform:

```powershell
$env:TF_VAR_admin_password = Read-Host 'Password' -AsSecureString |
                               ConvertFrom-SecureString -AsPlainText
```

### `OperationNotAllowed — VM SKU not available in zone`

Not all SKUs are available in every zone. Check:

```bash
az vm list-skus --location eastus --zone --output table | grep Standard_D2s_v5
```

Either choose a different zone or use a different SKU.

### `AuthorizationFailed` on extension deployment

The deploying identity needs **Virtual Machine Contributor** at minimum. Extensions that write to Log Analytics also need **Monitoring Contributor** on the workspace resource group.

### `CanNotDeleteLockExists` when redeploying

A `CanNotDelete` lock blocks deletions but **not updates**. If you applied a `ReadOnly` lock, remove it first:

```bash
az lock delete \
  --name "lock-vm-app-dev-eus-01" \
  --resource-group rg-compute-dev \
  --resource-name vm-app-dev-eus-01 \
  --resource-type Microsoft.Compute/virtualMachines
```

### Windows hostname too long

Windows computer names must be 15 characters or fewer. Set `computer_name` explicitly:

```hcl
computer_name = "APPPROD01"   # 15 chars max
```

### Terraform state lock

If a previous run was interrupted, the state may be locked. Check and unlock:

```bash
terraform force-unlock <lock-id>
```

Find the lock ID in the error message or in the Azure Storage blob metadata.
