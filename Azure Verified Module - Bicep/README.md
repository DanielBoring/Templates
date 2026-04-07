# Azure Verified Modules — Bicep Wrappers

Organisation-opinionated Bicep wrappers around [Azure Verified Modules (AVM)](https://azure.github.io/Azure-Verified-Modules/). Each wrapper enforces mandatory tagging, a consistent naming convention, and safe defaults, while exposing a simplified parameter surface. Consumers add one `.bicepparam` file per resource instance — the shared wrapper and `main.bicep` are never edited per-deployment.

---

## Modules

| Module | AVM resource | Description |
|---|---|---|
| [virtual-network/](virtual-network/) | `avm/res/network/virtual-network` | VNet with subnets, peerings, diagnostics, and resource lock |
| [virtual-machine/](virtual-machine/) | `avm/res/compute/virtual-machine` | Windows/Linux VM with AMA, Dependency Agent, Network Watcher, and auto-named disks |

---

## Common design principles

- **One file per resource** — copy the nearest `.bicepparam`, change only what differs, deploy.
- **Mandatory tags enforced** — `CostCenter`, `Owner`, and `BusinessUnit` are required; the deployment fails without them.
- **Naming convention built-in** — names follow `<type>-<workload>-<env>-<region-short>[-<instance>]`, overridable via `nameOverride` / `computerName`.
- **Pinned AVM versions** — version pins live in `modules/*-wrapper.bicep`; upgrading is a one-line change that all instances inherit.
- **`bicepconfig.json` per module** — sets the `br/public` alias and linting rules; keeps module references clean and IDE tooling working.

---

## Quick start

1. Navigate to the module folder.
2. Copy the closest example `.bicepparam` file in `parameters/`.
3. Edit only the values that differ for your resource.
4. Deploy via the helper script or Azure CLI:

```powershell
.\scripts\deploy.ps1 `
  -ParameterFile   .\parameters\<your-file>.bicepparam `
  -ResourceGroupName <rg-name> `
  -Location        <azure-region>
```

Full parameter references, secrets handling, CI/CD snippets, and troubleshooting guidance are in each module's README:

- [virtual-network/README.md](virtual-network/README.md)
- [virtual-machine/README.md](virtual-machine/README.md)

---

## Prerequisites

| Tool | Minimum version | Install |
|---|---|---|
| Azure CLI | 2.55+ | https://aka.ms/install-azure-cli |
| Bicep CLI | 0.26+ | `az bicep install` |
| PowerShell | 7.2+ | https://aka.ms/powershell |

```bash
az --version && az bicep version && pwsh --version
```
