# ============================================================
# Subscription / resource group
# ============================================================

variable "subscription_id" {
  description = "Azure subscription ID to deploy into."
  type        = string
}

variable "resource_group_name" {
  description = "Name of the existing resource group to deploy the VM into."
  type        = string
}

# ============================================================
# Naming inputs — drive the generated VM name
# ============================================================

variable "workload_name" {
  description = "Short role name for the VM. Used in the auto-generated name. Examples: app, dc, sql, web, mgmt."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,16}$", var.workload_name))
    error_message = "workload_name must be lowercase alphanumeric and hyphens, max 16 characters."
  }
}

variable "environment" {
  description = "Deployment environment. Drives the auto-generated name and the Environment tag."
  type        = string

  validation {
    condition     = contains(["prod", "nonprod", "staging", "test", "dev"], var.environment)
    error_message = "environment must be one of: prod, nonprod, staging, test, dev."
  }
}

variable "location" {
  description = "Azure region. Examples: eastus, westus2, australiaeast."
  type        = string
}

variable "instance_number" {
  description = "Two-digit instance suffix. Use '01' for the first instance, '02' for a second, etc."
  type        = string
  default     = "01"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.instance_number))
    error_message = "instance_number must be exactly two digits, e.g. '01'."
  }
}

variable "name_override" {
  description = "Bypass the generated name and use this value as the VM name. Leave empty to use the auto-generated name."
  type        = string
  default     = ""
}

# ============================================================
# VM configuration
# ============================================================

variable "os_type" {
  description = "Operating system type."
  type        = string

  validation {
    condition     = contains(["Windows", "Linux"], var.os_type)
    error_message = "os_type must be 'Windows' or 'Linux'."
  }
}

variable "vm_size" {
  description = "Azure VM SKU. Defaults to Standard_D2s_v5 (2 vCPU, 8 GB RAM, Premium SSD eligible)."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "source_image_reference" {
  description = "OS image to deploy. See README for common examples."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "admin_username" {
  description = "Local administrator username. Set via TF_VAR_admin_username environment variable — do not hard-code."
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Local administrator password. Required for Windows; optional for Linux when using SSH keys. Set via TF_VAR_admin_password — do not hard-code."
  type        = string
  sensitive   = true
  default     = ""
}

variable "subnet_id" {
  description = "Resource ID of the subnet to attach the primary NIC to."
  type        = string
}

variable "availability_zone" {
  description = "Availability zone number as a string ('1', '2', or '3'). Set to null to deploy with no zone pin."
  type        = string
  default     = null

  validation {
    condition     = var.availability_zone == null || contains(["1", "2", "3"], coalesce(var.availability_zone, "1"))
    error_message = "availability_zone must be '1', '2', '3', or null."
  }
}

# ============================================================
# OS disk
# ============================================================

variable "os_disk_size_gb" {
  description = "OS disk size in GB. Set to 0 to use the image default size."
  type        = number
  default     = 0
}

variable "os_disk_storage_account_type" {
  description = "OS disk storage SKU."
  type        = string
  default     = "Premium_LRS"

  validation {
    condition     = contains(["Standard_LRS", "StandardSSD_LRS", "Premium_LRS", "Premium_ZRS", "StandardSSD_ZRS"], var.os_disk_storage_account_type)
    error_message = "os_disk_storage_account_type must be a valid managed disk SKU."
  }
}

# ============================================================
# Data disks
# ============================================================

variable "data_disks" {
  description = "List of data disk definitions. The wrapper auto-generates disk names."
  type = list(object({
    disk_size_gb         = number
    lun                  = optional(number)
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadOnly")
  }))
  default = []
}

# ============================================================
# Linux-specific
# ============================================================

variable "disable_password_authentication" {
  description = "Linux only. Set to true to disable password authentication and require SSH keys."
  type        = bool
  default     = false
}

variable "ssh_public_keys" {
  description = "Linux SSH public keys. Each entry must include username and public_key."
  type = list(object({
    username   = string
    public_key = string
  }))
  default = []
}

# ============================================================
# Windows-specific
# ============================================================

variable "windows_patch_mode" {
  description = "Windows patch management mode. AutomaticByPlatform = Azure Update Manager (recommended)."
  type        = string
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["AutomaticByPlatform", "AutomaticByOS", "Manual"], var.windows_patch_mode)
    error_message = "windows_patch_mode must be AutomaticByPlatform, AutomaticByOS, or Manual."
  }
}

variable "linux_patch_mode" {
  description = "Linux patch management mode."
  type        = string
  default     = "AutomaticByPlatform"

  validation {
    condition     = contains(["AutomaticByPlatform", "ImageDefault"], var.linux_patch_mode)
    error_message = "linux_patch_mode must be AutomaticByPlatform or ImageDefault."
  }
}

variable "computer_name" {
  description = "Windows hostname (max 15 characters). Defaults to the VM name if empty. Set explicitly when the generated name exceeds 15 characters."
  type        = string
  default     = ""
}

variable "time_zone" {
  description = "Windows time zone. Recommended: 'UTC' for servers. Examples: 'Eastern Standard Time', 'AUS Eastern Standard Time'."
  type        = string
  default     = "UTC"
}

variable "license_type" {
  description = "Windows license type. Set to 'Windows_Server' to apply Azure Hybrid Benefit (~40% compute discount with SA licences)."
  type        = string
  default     = ""

  validation {
    condition     = contains(["", "Windows_Server", "Windows_Client"], var.license_type)
    error_message = "license_type must be '', 'Windows_Server', or 'Windows_Client'."
  }
}

# ============================================================
# Tags
# ============================================================

variable "mandatory_tags" {
  description = "Required organisational tags. Deployment fails validation without CostCenter, Owner, and BusinessUnit."
  type = object({
    CostCenter   = string
    Owner        = string
    BusinessUnit = string
  })
}

variable "additional_tags" {
  description = "Optional extra tags merged on top of mandatory_tags. Later keys win on collision."
  type        = map(string)
  default     = {}
}

# ============================================================
# Extensions
# ============================================================

variable "enable_azure_monitor_agent" {
  description = "Install Azure Monitor Agent. Required for VM Insights, Sentinel data collection, and Update Manager. Automatically enables system-assigned managed identity."
  type        = bool
  default     = true
}

variable "enable_dependency_agent" {
  description = "Install VM Insights Dependency Agent (maps network connections). Requires enable_azure_monitor_agent = true."
  type        = bool
  default     = true
}

variable "enable_network_watcher_agent" {
  description = "Install Network Watcher Agent. Required for NSG flow logs, connection monitor, and packet capture."
  type        = bool
  default     = true
}

variable "enable_antimalware" {
  description = "Install Microsoft Antimalware extension. Windows only. Enable on all production Windows VMs."
  type        = bool
  default     = false
}

variable "enable_entra_id_join" {
  description = "Join the VM to Microsoft Entra ID. Enables passwordless sign-in and Conditional Access. Requires Entra ID P1."
  type        = bool
  default     = false
}

# ============================================================
# Governance
# ============================================================

variable "resource_lock" {
  description = "Resource lock level. Use 'CanNotDelete' for production VMs."
  type        = string
  default     = "None"

  validation {
    condition     = contains(["None", "CanNotDelete", "ReadOnly"], var.resource_lock)
    error_message = "resource_lock must be 'None', 'CanNotDelete', or 'ReadOnly'."
  }
}

variable "log_analytics_workspace_id" {
  description = "Resource ID of a Log Analytics workspace. When set, VM diagnostic metrics are sent to this workspace."
  type        = string
  default     = ""
}

variable "enable_boot_diagnostics" {
  description = "Enable boot diagnostics using Azure-managed storage. Enables screenshot and serial console access."
  type        = bool
  default     = true
}

variable "enable_telemetry" {
  description = "Send anonymous usage telemetry to Microsoft. Helps the AVM team prioritise improvements. Set to false to opt out."
  type        = bool
  default     = true
}
