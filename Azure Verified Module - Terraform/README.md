# Azure Terraform Verified Modules — Lesson

A practical guide to understanding, adopting, and scaling **Azure Verified Modules (AVM)** using Terraform — Microsoft's official library of production-ready infrastructure-as-code modules.

---

## Table of Contents

1. [What are Azure Verified Modules?](#1-what-are-azure-verified-modules)
2. [When to use AVM](#2-when-to-use-avm)
3. [Why use AVM](#3-why-use-avm)
4. [How to scale AVM use](#4-how-to-scale-avm-use)
5. [The wrapper pattern](#5-the-wrapper-pattern)
6. [Module catalogue — common resources](#6-module-catalogue--common-resources)
7. [AVM vs the alternatives](#7-avm-vs-the-alternatives)
8. [Lab](#8-lab)

---

## 1. What are Azure Verified Modules?

**Azure Verified Modules (AVM)** is Microsoft's official library of production-ready, standardised infrastructure-as-code modules for both Bicep and Terraform. Every AVM module is:

| Property | Detail |
|---|---|
| **Owned by Microsoft** | Authored and maintained by Microsoft engineering teams, not community volunteers |
| **End-to-end tested** | Automated tests run against a real Azure subscription on every release |
| **Semantically versioned** | `MAJOR.MINOR.PATCH` — breaking changes only in major versions |
| **Consistent interface** | Every module exposes the same concepts: `tags`, `lock`, `diagnostic_settings`, `role_assignments`, `managed_identities`, `enable_telemetry` |
| **Discoverable** | Published to the [Terraform Registry](https://registry.terraform.io/browse/modules?q=Azure%2Favm) under the `Azure/` namespace |

### What AVM replaces

AVM replaces the older **Terraform-AzureRM** community module pattern (`github.com/Azure/terraform-azurerm-*`) and the Terraform landing zone modules. Those libraries lacked consistent interfaces, were unevenly tested, and had inconsistent support commitments. AVM is the single, strategic replacement.

### How an AVM Terraform module is consumed

Every AVM module is published to the public Terraform Registry. You reference it like any other module:

```hcl
module "virtual_machine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "~> 0.17"

  name                = "vm-app-prod-eus-01"
  resource_group_name = "rg-compute-prod"
  location            = "eastus"
  os_type             = "Windows"
  sku_size            = "Standard_D2s_v5"
  # ... additional inputs
}
```

Terraform downloads the module from the registry during `terraform init`. No local copy is required.

### AVM module naming convention

All AVM Terraform modules follow the naming pattern:

```
Azure/avm-<type>-<provider>-<resource>/azurerm
```

| Segment | Meaning | Example |
|---|---|---|
| `avm` | AVM prefix | |
| `res` | Resource module (deploys one Azure resource type) | `avm-res-compute-virtualmachine` |
| `ptn` | Pattern module (deploys multiple resources forming a pattern) | `avm-ptn-network-private-link-private-dns-zones` |
| `utl` | Utility module (shared helpers — telemetry, naming, etc.) | `avm-utl-regions` |

---

## 2. When to use AVM

### Use AVM when:

- **You are deploying Azure resources in a production or shared environment** and want a tested, supportable baseline
- **Governance is mandatory** — your organisation requires consistent tagging, resource locks, RBAC assignments, or diagnostic settings on every resource
- **You are building a platform or landing zone** that other teams will deploy onto
- **You want Microsoft's deployment opinionations** — encryption at rest, private endpoints, boot diagnostics, managed identities — enabled by default
- **You need predictable upgrades** — semantic versioning means you can pin a version and upgrade deliberately

### Consider alternatives when:

| Scenario | Better approach |
|---|---|
| Prototyping / learning | Raw `azurerm_*` resources — fewer layers, easier to understand |
| Highly custom resource shapes not covered by AVM | Write your own module from the provider directly |
| Very simple, one-off deployments | Inline `azurerm_*` resources in a root module |
| The AVM module doesn't exist yet for your resource | Check the AVM backlog — file an issue, or use the provider directly |

### Decision framework

```
Is this going into production or shared infrastructure?
  YES → Are you willing to accept AVM's opinionated defaults?
          YES → Use AVM (direct or via wrapper)
          NO  → Consider writing a thin wrapper around AVM to override defaults
  NO  → Prototype with raw azurerm_* resources; migrate to AVM before prod
```

---

## 3. Why use AVM

### 3.1 Tested by Microsoft

Every AVM module is tested with end-to-end tests that deploy real Azure resources in a real subscription. When a release passes, you know the code actually works. Community modules and hand-rolled code rarely have this level of testing.

### 3.2 Security defaults out of the box

AVM modules apply Microsoft's recommended security configuration by default:

- **Encryption at rest** — managed disks, storage accounts, and key vaults use platform-managed keys unless you provide your own
- **Boot diagnostics** — enabled by default on VM modules
- **Private endpoints** — supported on all compatible resources
- **Managed identity** — modules accept and wire `managed_identities` consistently
- **No public IPs** — most modules default to private-only; you opt in to public exposure

### 3.3 Consistent cross-resource interface

Every AVM module, regardless of resource type, exposes the same governance parameters:

| Parameter | Purpose |
|---|---|
| `tags` | Resource tags — merged with org mandatory tags in wrappers |
| `lock` | Resource lock (`CanNotDelete` or `ReadOnly`) |
| `diagnostic_settings` | Send logs and metrics to Log Analytics, Event Hub, or Storage |
| `role_assignments` | RBAC assignments scoped to the resource |
| `managed_identities` | System-assigned and user-assigned identity attachment |
| `enable_telemetry` | Anonymous usage telemetry to Microsoft (opt-out available) |

Once you learn one AVM module, the governance layer of every other module works identically.

### 3.4 Versioned, predictable upgrades

AVM follows semantic versioning strictly. When you pin `version = "~> 0.17"`:
- Patch updates (`0.17.1 → 0.17.2`) are applied automatically by `terraform init -upgrade`
- Minor updates (`0.17 → 0.18`) require a version bump — you review the changelog first
- Breaking changes only happen in major versions with explicit migration guidance

This is far more predictable than Git-sourced modules or modules with no versioning.

### 3.5 Reduced cognitive load

AVM modules expose 40–80 parameters for complex resources. Your wrapper reduces that to the 8–15 parameters that actually vary per instance. Teams deploying VMs don't need to know what `nicConfigurations` looks like — they provide a subnet ID and the wrapper builds it.

### 3.6 One upgrade path

When Microsoft releases an updated AVM module version, you update one line in your wrapper. All VMs built from that wrapper inherit the update on next apply. Without a wrapper pattern, you'd update every Terraform root module individually.

---

## 4. How to scale AVM use

### 4.1 The two-layer model

Scaling AVM in an organisation typically involves two layers:

```
┌─────────────────────────────────────────────────────────────┐
│  Layer 2: Consumer  (application team Terraform root module) │
│                                                               │
│  module "app_vm" {                                            │
│    source         = "git::https://your-org/tf-modules//vm"   │
│    workload_name  = "app"                                     │
│    environment    = "prod"                                    │
│    subnet_id      = data.azurerm_subnet.app.id                │
│    mandatory_tags = local.org_tags                            │
│  }                                                            │
└──────────────────┬──────────────────────────────────────────┘
                   │ calls
┌──────────────────▼──────────────────────────────────────────┐
│  Layer 1: Org wrapper  (platform team, your modules/ folder)  │
│                                                               │
│  module "virtual_machine" {                                   │
│    source  = "Azure/avm-res-compute-virtualmachine/azurerm"  │
│    version = "~> 0.17"                                        │
│    # ... org defaults enforced here                           │
│  }                                                            │
└──────────────────┬──────────────────────────────────────────┘
                   │ calls
┌──────────────────▼──────────────────────────────────────────┐
│  Layer 0: AVM  (Microsoft, Terraform Registry)               │
│  Azure/avm-res-compute-virtualmachine/azurerm ~> 0.17        │
└─────────────────────────────────────────────────────────────┘
```

Layer 2 (consumer) only changes per-VM values. Layer 1 (wrapper) holds org policy. Layer 0 (AVM) is Microsoft's tested code.

### 4.2 Publish your wrappers to a private module registry

For large organisations, publish Layer 1 wrappers to:
- **Terraform Cloud/Enterprise** — built-in private module registry with versioning
- **Azure DevOps Artifacts** — host as a Git module source with tags
- **GitHub** — reference with Git tags: `git::https://github.com/your-org/tf-modules.git//vm?ref=v2.1.0`

Teams consume the wrapper without needing to understand the AVM interface at all.

### 4.3 Pin module versions explicitly

Always pin AVM versions in your wrappers. Never use `version = ">= 0.17"` (unbounded) or omit the version:

```hcl
# Correct — patch updates allowed, minor requires deliberate bump
version = "~> 0.17"

# Wrong — may break on any release
version = ">= 0.1"
```

Document your upgrade process: when to test, when to promote from dev to prod, who approves.

### 4.4 CI/CD fleet deployments

Scale to many resources with a CI/CD matrix strategy. Each `.tfvars` file represents one instance. The pipeline loops over them:

**GitHub Actions:**
```yaml
strategy:
  matrix:
    instance:
      - { name: vm-app-prod-01, env: environments/vm-app-prod-01.tfvars, rg: rg-compute-prod }
      - { name: vm-app-prod-02, env: environments/vm-app-prod-02.tfvars, rg: rg-compute-prod }
      - { name: vm-dc-prod-01,  env: environments/vm-dc-prod-01.tfvars,  rg: rg-identity-prod }

steps:
  - name: Terraform Plan
    run: |
      terraform plan \
        -var-file="${{ matrix.instance.env }}" \
        -var="resource_group_name=${{ matrix.instance.rg }}" \
        -out="${{ matrix.instance.name }}.tfplan"
```

**Azure DevOps:**
```yaml
- ${{ each vm in parameters.vms }}:
  - task: TerraformCLI@0
    displayName: 'Plan ${{ vm.name }}'
    inputs:
      command: plan
      commandOptions: '-var-file="environments/${{ vm.varFile }}"'
```

### 4.5 Terraform workspaces vs separate state files

Two common patterns for state isolation:

| Pattern | When to use |
|---|---|
| **One workspace per environment** (`terraform workspace new prod`) | Small teams, simple promotion — dev/staging/prod share one module, different state |
| **One state file per VM instance** | Large fleets — each VM has its own state, failures are isolated |

For the fleet/VM pattern, one state file per instance is recommended. Use Azure Storage as the backend:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-terraform-state"
    storage_account_name = "sttfstateprod"
    container_name       = "tfstate"
    key                  = "vm-app-prod-01.tfstate"
  }
}
```

### 4.6 Governance at scale — Azure Policy + AVM

AVM modules produce resources that are naturally policy-compliant because they:
- Accept `tags` (policy: require tags)
- Accept `lock` (policy: require delete locks on prod)
- Accept `diagnostic_settings` (policy: require diagnostic settings)

Use Azure Policy to audit or enforce, and let AVM modules satisfy the requirements declaratively. Wrappers that set organisational defaults make policy compliance automatic for consumers.

---

## 5. The wrapper pattern

This section summarises the wrapper pattern used in the lab. Full implementation is in [virtual-machine/](virtual-machine/).

### Why wrap?

The upstream AVM VM module has 80+ input variables. A wrapper:

1. **Enforces defaults** — Azure Monitor Agent, boot diagnostics, and network watcher are on by default; teams opt out deliberately
2. **Generates names** — `vm-<workload>-<env>-<region>-<instance>` from a few short inputs
3. **Auto-names child resources** — OS disk: `<vmname>-osdisk`; data disks: `<vmname>-datadisk-01`, `<vmname>-datadisk-02`
4. **Simplifies NICs** — a subnet ID + two bools replaces the full `network_interfaces` map
5. **Centralises upgrades** — update the AVM version in one file; all VMs inherit it
6. **Guards against drift** — `validation {}` blocks on `environment` and `os_type` prevent invalid values

### What the wrapper does NOT do

A wrapper should not be a kitchen-sink module. It:
- Does not create the resource group
- Does not create the VNet or subnet
- Does not create Key Vault or manage secrets
- Does not deploy applications or DSC configurations

Those are separate modules with separate lifecycles.

---

## 6. Module catalogue — common resources

| Resource | AVM Module | Registry |
|---|---|---|
| Virtual Machine | `Azure/avm-res-compute-virtualmachine/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-compute-virtualmachine/azurerm) |
| Virtual Network | `Azure/avm-res-network-virtualnetwork/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-network-virtualnetwork/azurerm) |
| Key Vault | `Azure/avm-res-keyvault-vault/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-keyvault-vault/azurerm) |
| Storage Account | `Azure/avm-res-storage-storageaccount/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-storage-storageaccount/azurerm) |
| App Service / Web App | `Azure/avm-res-web-site/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-web-site/azurerm) |
| SQL Database | `Azure/avm-res-sql-server/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-sql-server/azurerm) |
| AKS | `Azure/avm-res-containerservice-managedcluster/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-containerservice-managedcluster/azurerm) |
| Log Analytics Workspace | `Azure/avm-res-operationalinsights-workspace/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-operationalinsights-workspace/azurerm) |
| Private DNS Zone | `Azure/avm-res-network-privatednszone/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm) |
| User-Assigned Managed Identity | `Azure/avm-res-managedidentity-userassignedidentity/azurerm` | [link](https://registry.terraform.io/modules/Azure/avm-res-managedidentity-userassignedidentity/azurerm) |

Browse the full catalogue: https://azure.github.io/Azure-Verified-Modules/

---

## 7. AVM vs the alternatives

| Approach | Tested by MS | Consistent interface | Versioned | When to choose |
|---|---|---|---|---|
| **AVM** | Yes | Yes | Yes | Production, shared platforms, governed environments |
| **azurerm_* resources directly** | N/A (provider) | N/A | Via provider | Prototyping, unsupported resources, maximum control |
| **Community modules** (registry.terraform.io/hashicorp/*) | Varies | No | Yes | Small projects, well-maintained community modules |
| **Custom internal modules** | Only if you write tests | Only if you enforce it | Only if you tag | When AVM doesn't cover your requirements |
| **Terraform Cloud IaC automation** | N/A | N/A | N/A | Orchestration layer on top of modules |

---

## 8. Lab

The lab deploys a Windows or Linux virtual machine using the wrapper pattern described above.

**Lab location:** [virtual-machine/](virtual-machine/)

**Step-by-step instructions:** [virtual-machine/RUNBOOK.md](virtual-machine/RUNBOOK.md)

**What you will build:**

```
Azure Subscription
└── rg-compute-dev
    └── vm-app-dev-eus-01
        ├── nic-vm-app-dev-eus-01-01
        ├── vm-app-dev-eus-01-osdisk
        └── Extensions: AMA, DependencyAgent, NetworkWatcher
```

**Skills practised:**
- Referencing an AVM module from the Terraform Registry
- Writing an org wrapper module with opinionated defaults
- Parameterising deployments with `.tfvars` files
- Managing secrets with environment variables (`TF_VAR_*`)
- Running `terraform init`, `plan`, and `apply`
- Reviewing infrastructure changes before applying
- Cleaning up with `terraform destroy`
