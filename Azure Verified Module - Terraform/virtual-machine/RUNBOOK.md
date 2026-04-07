# Lab Runbook — Deploy an Azure VM with Terraform AVM

**Estimated time:** 30–45 minutes  
**Difficulty:** Beginner–Intermediate  
**What you will deploy:** A Windows Server 2022 VM in Azure using the AVM wrapper pattern

---

## Before you start — what you will learn

By the end of this lab you will be able to:

1. Explain what a Terraform Azure Verified Module is and why it exists
2. Describe the wrapper pattern and why organisations use it
3. Navigate the Terraform AVM registry to find a module
4. Run a complete Terraform workflow: `init` → `plan` → `apply` → `destroy`
5. Manage deployment secrets safely using environment variables
6. Read a `terraform plan` output and understand what will be created

---

## Prerequisites checklist

Work through this checklist before starting the lab. Each step includes a verification command.

### Step 1 — Install Terraform

Download and install Terraform 1.9 or later from https://developer.hashicorp.com/terraform/install

Verify:
```powershell
terraform version
```

Expected output (version number may differ):
```
Terraform v1.9.x
on windows_amd64
```

If you see `command not found`, add the Terraform binary to your PATH and restart your terminal.

---

### Step 2 — Install Azure CLI

Download and install Azure CLI 2.55+ from https://aka.ms/install-azure-cli

Verify:
```powershell
az --version
```

Expected output (first line):
```
azure-cli                         2.x.x
```

---

### Step 3 — Install PowerShell 7

Download from https://aka.ms/powershell

Verify:
```powershell
pwsh --version
```

Expected output:
```
PowerShell 7.x.x
```

---

### Step 4 — Log in to Azure

```powershell
az login
```

A browser window will open. Sign in with your Azure account. After signing in, return to the terminal.

List your subscriptions and confirm you can see the one you want to use:
```powershell
az account list --output table
```

Set the target subscription:
```powershell
az account set --subscription "YOUR-SUBSCRIPTION-ID-HERE"
```

Verify:
```powershell
az account show --query '{name:name, id:id}' -o table
```

---

### Step 5 — RBAC check

You need **Contributor** or **Virtual Machine Contributor** on the target resource group.

```powershell
# List your role assignments on the subscription
az role assignment list --assignee (az ad signed-in-user show --query id -o tsv) `
  --output table
```

If you see `Contributor` or `Owner`, you are good to proceed.

---

## Lab — Deploy a Virtual Machine

### Step 6 — Navigate to the lab directory

```powershell
# From the repo root
cd "Azure Verified Module - Terraform/virtual-machine"
```

Confirm the structure is correct:
```powershell
ls
```

Expected output:
```
providers.tf
main.tf
variables.tf
outputs.tf
terraform.tfvars.example
environments/
modules/
scripts/
RUNBOOK.md
```

---

### Step 7 — Explore the AVM module on the registry

Before writing any code, look at what you are consuming.

1. Open your browser and go to:  
   `https://registry.terraform.io/modules/Azure/avm-res-compute-virtualmachine/azurerm`

2. Review:
   - **Inputs tab** — notice there are 80+ input variables
   - **Outputs tab** — note `resource_id`, `name`, `private_ip_addresses`
   - **Readme tab** — read the "Features" section

3. Now open `modules/vm-wrapper/main.tf` in your editor.

   > **Key observation:** The wrapper collapses those 80+ inputs to ~25 variables that consumers actually need to vary. Everything else is an org-enforced default.

---

### Step 8 — Create a resource group

The module deploys into an existing resource group. Create one now:

```powershell
az group create `
  --name rg-avm-lab-dev `
  --location eastus `
  --tags Environment=dev ManagedBy=Terraform Owner=lab-student
```

Expected output:
```json
{
  "location": "eastus",
  "name": "rg-avm-lab-dev",
  ...
}
```

---

### Step 9 — Get a subnet resource ID

The VM needs a subnet to connect to. For this lab, either:

**Option A — Use an existing VNet/subnet (if you have one)**

```powershell
# List VNets in your subscription
az network vnet list --output table

# Get the subnet ID
az network vnet subnet show `
  --resource-group YOUR-VNET-RG `
  --vnet-name YOUR-VNET-NAME `
  --name YOUR-SUBNET-NAME `
  --query id -o tsv
```

Copy the output — it looks like:
```
/subscriptions/00000000-.../resourceGroups/rg-network-dev/providers/Microsoft.Network/virtualNetworks/vnet-hub-dev/subnets/snet-compute-dev
```

**Option B — Create a minimal VNet for the lab**

```powershell
# Create a VNet
az network vnet create `
  --resource-group rg-avm-lab-dev `
  --name vnet-lab `
  --address-prefix 10.100.0.0/16 `
  --location eastus

# Create a subnet
az network vnet subnet create `
  --resource-group rg-avm-lab-dev `
  --vnet-name vnet-lab `
  --name snet-compute `
  --address-prefix 10.100.1.0/24

# Get the subnet ID
az network vnet subnet show `
  --resource-group rg-avm-lab-dev `
  --vnet-name vnet-lab `
  --name snet-compute `
  --query id -o tsv
```

Save the subnet ID — you will need it in the next step.

---

### Step 10 — Prepare your tfvars file

Copy the Windows dev example. The `.example` suffix keeps the template in source control while the real file (with your actual IDs) stays out of git:

```powershell
Copy-Item environments/vm-windows-dev.tfvars.example environments/vm-lab.tfvars
```

Open `environments/vm-lab.tfvars` in your editor and update these values:

```hcl
# ---- Update these ----
subscription_id     = "YOUR-SUBSCRIPTION-ID"        # From: az account show --query id -o tsv
resource_group_name = "rg-avm-lab-dev"

subnet_id = "PASTE-YOUR-SUBNET-ID-HERE"             # From Step 9

# ---- Leave these as-is for the lab ----
workload_name   = "lab"
environment     = "dev"
location        = "eastus"
instance_number = "01"
os_type         = "Windows"
vm_size         = "Standard_B2ms"                   # Cost-optimised for lab use
```

Save the file.

> **Subscription ID:** Run `az account show --query id -o tsv` if you don't have it.

---

### Step 11 — Set credentials as environment variables

**Never put credentials in your tfvars file.** Set them as environment variables instead:

```powershell
# Username
$env:TF_VAR_admin_username = 'labadmin'

# Password (must meet Azure complexity requirements):
#   - At least 12 characters
#   - Uppercase, lowercase, number, and symbol
$env:TF_VAR_admin_password = 'LabP@ssw0rd123!'
```

Verify they are set:
```powershell
# Should print "labadmin" (not blank)
echo $env:TF_VAR_admin_username
```

> **Why environment variables?** Terraform reads `TF_VAR_<name>` automatically. The values never touch disk and are not committed to source control. This matches how CI/CD pipelines inject secrets.

---

### Step 12 — Terraform init

Download the AVM module from the Terraform Registry:

```powershell
terraform init
```

Expected output (partial):
```
Initializing modules...
Downloading registry.terraform.io/Azure/avm-res-compute-virtualmachine/azurerm 0.17.x for vm.virtual_machine...

Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/azurerm versions matching "~> 4.0"...
- Installing hashicorp/azurerm v4.x.x...

Terraform has been successfully initialized!
```

> **What just happened?** Terraform downloaded:
> 1. The `Azure/avm-res-compute-virtualmachine/azurerm` module from the public registry
> 2. The `hashicorp/azurerm` provider (~4.x)
> 3. The `hashicorp/random` provider
>
> These are cached in `.terraform/` — never commit this directory.

---

### Step 13 — Terraform plan (dry run)

Preview all changes **without creating anything**:

```powershell
terraform plan -var-file="environments/vm-lab.tfvars"
```

Read the output carefully. You should see approximately:

```
Terraform will perform the following actions:

  # module.vm.module.virtual_machine.azurerm_windows_virtual_machine.this will be created
  + resource "azurerm_windows_virtual_machine" "this" {
      + name                  = "vm-lab-dev-eus-01"
      + location              = "eastus"
      + resource_group_name   = "rg-avm-lab-dev"
      + size                  = "Standard_B2ms"
      ...
    }

  # module.vm.module.virtual_machine.azurerm_network_interface.this["nic_primary"] will be created
  + resource "azurerm_network_interface" "this" {
      + name = "nic-vm-lab-dev-eus-01-01"
      ...
    }

  # module.vm.module.virtual_machine.azurerm_managed_disk.this["osdisk"] will be created
  ...

Plan: 8 to add, 0 to change, 0 to destroy.
```

**Lab exercise — answer these questions from the plan output:**

1. What is the generated VM name? (Look for `name = "vm-..."`)
2. What NIC name was auto-generated? (Look for `azurerm_network_interface`)
3. What OS disk name was auto-generated? (Look for `azurerm_managed_disk` with `osdisk` in the name)
4. How many resources in total will be created? (Look for `Plan: X to add`)
5. Are any extensions being deployed? (Look for `azurerm_virtual_machine_extension`)

---

### Step 14 — Deploy with the helper script (recommended)

Use the deploy script for an interactive, guided deployment:

```powershell
.\scripts\deploy.ps1 -VarFile environments/vm-lab.tfvars
```

The script will:
1. Check tools are installed
2. Verify environment variables are set
3. Show current subscription context
4. Run `terraform plan` and display the output
5. Prompt you to type `yes` to confirm before applying

When prompted, review the plan and type `yes`:

```
  You are about to APPLY resources using: environments/vm-lab.tfvars
  Review the plan output above carefully.

  Type 'yes' to proceed, anything else to cancel: yes
```

**Alternatively, apply directly:**

```powershell
terraform apply -var-file="environments/vm-lab.tfvars"
```

---

### Step 15 — Monitor deployment progress

The deployment will take approximately **5–10 minutes**. You will see Terraform creating resources in sequence:

```
module.vm.module.virtual_machine.azurerm_network_interface.this["nic_primary"]: Creating...
module.vm.module.virtual_machine.azurerm_network_interface.this["nic_primary"]: Creation complete after 3s
module.vm.module.virtual_machine.azurerm_windows_virtual_machine.this: Creating...
module.vm.module.virtual_machine.azurerm_windows_virtual_machine.this: Still creating... [10s elapsed]
...
module.vm.module.virtual_machine.azurerm_windows_virtual_machine.this: Creation complete after 4m32s

Apply complete! Resources: 8 added, 0 changed, 0 destroyed.

Outputs:

private_ip_address                    = "10.100.1.4"
system_assigned_identity_principal_id = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
vm_id                                 = "/subscriptions/.../virtualMachines/vm-lab-dev-eus-01"
vm_name                               = "vm-lab-dev-eus-01"
```

---

### Step 16 — Verify in the Azure portal

1. Open the [Azure portal](https://portal.azure.com) and navigate to **Resource groups → rg-avm-lab-dev**
2. Confirm you see the VM, NIC, OS disk, and extensions listed as resources
3. Click the VM → **Extensions + applications** — you should see:
   - AzureMonitorWindowsAgent
   - DependencyAgentWindows
   - NetworkWatcherAgentWindows
4. Click the VM → **Boot diagnostics** — confirm it is enabled

---

### Step 17 — Verify outputs

Check Terraform's recorded outputs:

```powershell
terraform output
```

Expected:
```
private_ip_address                    = "10.100.x.x"
system_assigned_identity_principal_id = "xxxxxxxx-..."
vm_id                                 = "/subscriptions/..."
vm_name                               = "vm-lab-dev-eus-01"
```

Show a specific output:
```powershell
terraform output vm_name
```

---

### Step 18 — Inspect Terraform state

Terraform tracks deployed resources in a **state file** (`terraform.tfstate`). Explore it:

```powershell
# List all resources tracked in state
terraform state list
```

Expected output:
```
module.vm.module.virtual_machine.azurerm_windows_virtual_machine.this
module.vm.module.virtual_machine.azurerm_network_interface.this["nic_primary"]
module.vm.module.virtual_machine.azurerm_managed_disk.this["osdisk"]
module.vm.module.virtual_machine.azurerm_virtual_machine_extension.this["AzureMonitorWindowsAgent"]
...
```

Show details of the VM in state:
```powershell
terraform state show 'module.vm.module.virtual_machine.azurerm_windows_virtual_machine.this'
```

> **Important:** In production, store state in Azure Blob Storage — not a local file. Local state is lost if your machine is wiped. See the backend configuration in `README.md` section 3.

---

### Step 19 — Make a change (optional bonus exercise)

Add an additional tag without redeploying the whole VM. Edit `environments/vm-lab.tfvars`:

```hcl
additional_tags = {
  AutoShutdown = "1900"
  Criticality  = "Low"
  LabStudent   = "your-name-here"    # Add this line
}
```

Run a plan to see what will change:
```powershell
terraform plan -var-file="environments/vm-lab.tfvars"
```

You should see:
```
  ~ resource "azurerm_windows_virtual_machine" "this" {
      ~ tags = {
          + "LabStudent" = "your-name-here"
        }
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

Apply the change:
```powershell
terraform apply -var-file="environments/vm-lab.tfvars"
```

> **Key lesson:** Terraform only changes what is different. Adding a tag does not recreate the VM — it issues a tag update API call. The VM stays running.

---

### Step 20 — Clean up (destroy)

> **Important:** Always destroy lab resources when you are done to avoid unnecessary Azure costs.

Preview what will be destroyed:
```powershell
terraform plan -destroy -var-file="environments/vm-lab.tfvars"
```

Destroy all resources:
```powershell
.\scripts\deploy.ps1 -VarFile environments/vm-lab.tfvars -Destroy
```

Or directly:
```powershell
terraform destroy -var-file="environments/vm-lab.tfvars"
```

Type `yes` when prompted.

After destroy completes:
```powershell
# Verify no resources remain
az resource list --resource-group rg-avm-lab-dev --output table
```

Delete the resource group (if you created it for this lab):
```powershell
az group delete --name rg-avm-lab-dev --yes --no-wait
```

---

## Lab review

Congratulations on completing the lab. You have:

| Task | Done |
|---|---|
| Installed and verified all required tools | |
| Authenticated to Azure and set the target subscription | |
| Explored the AVM VM module on the Terraform Registry | |
| Created a resource group and VNet/subnet for the lab | |
| Prepared a `.tfvars` file for a specific VM instance | |
| Set credentials safely as environment variables | |
| Ran `terraform init` and downloaded the AVM module | |
| Read and interpreted a `terraform plan` output | |
| Deployed a VM with all required extensions via `terraform apply` | |
| Verified the deployment in the Azure portal | |
| Inspected Terraform state with `terraform state list` | |
| Made a non-destructive change and observed the incremental plan | |
| Destroyed all resources cleanly with `terraform destroy` | |

---

## Knowledge check questions

Answer these without looking at the materials — they test your understanding, not just your ability to follow steps.

1. What is the difference between an AVM `res` module and an AVM `ptn` module?

2. If the AVM VM module exposes 80+ variables, why does the wrapper only expose ~25?

3. You need to deploy the same VM module to three environments (dev, staging, prod). What file do you create for each environment, and what files stay the same?

4. A colleague says "just put the admin password in the `.tfvars` file, it's fine for dev." What is your response?

5. After `terraform apply`, a security team requirement says all production VMs must have a `CanNotDelete` resource lock. Which variable do you change, and in which file?

6. The AVM module releases version `0.18.0` with a minor breaking change to the `network_interfaces` schema. Walk through the steps to evaluate and apply this upgrade safely.

7. You run `terraform plan` and see `Plan: 0 to add, 0 to change, 1 to destroy` — but you only changed a tag. What likely happened?

8. Your organisation wants 15 VMs deployed from this module. How would you structure the CI/CD pipeline to deploy all 15 without writing the pipeline steps 15 times?

---

## Next steps

- **Add a data disk:** Edit the `data_disks` variable in your `.tfvars` file and redeploy.
- **Deploy a Linux VM:** Use `environments/vm-linux-dev.tfvars` and generate an SSH key pair.
- **Enable Antimalware:** Set `enable_antimalware = true` on a Windows VM and apply.
- **Add a resource lock:** Set `resource_lock = "CanNotDelete"` and verify it in the portal.
- **Remote state:** Configure an Azure Storage backend in `providers.tf` and migrate state with `terraform init -migrate-state`.
- **Add a second VM:** Create `environments/vm-lab-02.tfvars` with `instance_number = "02"` and deploy it alongside the first.
