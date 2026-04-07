# ============================================================
# Naming
# ============================================================

variable "workload_name" {
  description = "Short role name. Used to generate the VM name."
  type        = string
}

variable "environment" {
  description = "Deployment environment: prod, nonprod, staging, test, or dev."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "instance_number" {
  description = "Two-digit instance suffix."
  type        = string
  default     = "01"
}

variable "name_override" {
  description = "Override the generated name. Leave empty to use auto-generated name."
  type        = string
  default     = ""
}

# ============================================================
# Placement
# ============================================================

variable "resource_group_name" {
  description = "Name of the existing resource group."
  type        = string
}

variable "availability_zone" {
  description = "Availability zone pin ('1', '2', '3') or null."
  type        = string
  default     = null
}

# ============================================================
# VM spec
# ============================================================

variable "os_type" {
  description = "'Windows' or 'Linux'."
  type        = string
}

variable "vm_size" {
  description = "Azure VM SKU."
  type        = string
  default     = "Standard_D2s_v5"
}

variable "source_image_reference" {
  description = "OS image reference."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

# ============================================================
# Credentials
# ============================================================

variable "admin_username" {
  description = "Local administrator username."
  type        = string
  sensitive   = true
}

variable "admin_password" {
  description = "Local administrator password. Required for Windows; leave empty for Linux SSH-only VMs."
  type        = string
  sensitive   = true
  default     = ""
}

variable "disable_password_authentication" {
  description = "Linux only. Disable password auth and require SSH keys."
  type        = bool
  default     = false
}

variable "ssh_public_keys" {
  description = "Linux SSH public keys. Each entry requires username and public_key."
  type = list(object({
    username   = string
    public_key = string
  }))
  default = []
}

# ============================================================
# Networking
# ============================================================

variable "subnet_id" {
  description = "Resource ID of the subnet for the primary NIC."
  type        = string
}

# ============================================================
# Disks
# ============================================================

variable "os_disk_size_gb" {
  description = "OS disk size in GB. 0 = image default."
  type        = number
  default     = 0
}

variable "os_disk_storage_account_type" {
  description = "OS disk storage SKU."
  type        = string
  default     = "Premium_LRS"
}

variable "data_disks" {
  description = "Simplified data disk list. The wrapper generates names automatically."
  type = list(object({
    disk_size_gb         = number
    lun                  = optional(number)
    storage_account_type = optional(string, "Premium_LRS")
    caching              = optional(string, "ReadOnly")
  }))
  default = []
}

# ============================================================
# OS-specific
# ============================================================

variable "windows_patch_mode" {
  description = "Windows patch mode."
  type        = string
  default     = "AutomaticByPlatform"
}

variable "linux_patch_mode" {
  description = "Linux patch mode."
  type        = string
  default     = "AutomaticByPlatform"
}

variable "computer_name" {
  description = "Windows hostname override (max 15 chars). Defaults to VM name if empty."
  type        = string
  default     = ""
}

variable "time_zone" {
  description = "Windows time zone."
  type        = string
  default     = "UTC"
}

variable "license_type" {
  description = "Windows license type for Azure Hybrid Benefit."
  type        = string
  default     = ""
}

# ============================================================
# Tags
# ============================================================

variable "mandatory_tags" {
  description = "Required org tags: CostCenter, Owner, BusinessUnit."
  type = object({
    CostCenter   = string
    Owner        = string
    BusinessUnit = string
  })
}

variable "additional_tags" {
  description = "Extra tags merged after mandatory_tags."
  type        = map(string)
  default     = {}
}

# ============================================================
# Extensions
# ============================================================

variable "enable_azure_monitor_agent" {
  description = "Install Azure Monitor Agent. Also enables system-assigned identity."
  type        = bool
  default     = true
}

variable "enable_dependency_agent" {
  description = "Install VM Insights Dependency Agent. Requires AMA."
  type        = bool
  default     = true
}

variable "enable_network_watcher_agent" {
  description = "Install Network Watcher Agent."
  type        = bool
  default     = true
}

variable "enable_antimalware" {
  description = "Install Microsoft Antimalware (Windows only)."
  type        = bool
  default     = false
}

variable "enable_entra_id_join" {
  description = "Join the VM to Microsoft Entra ID."
  type        = bool
  default     = false
}

# ============================================================
# Governance
# ============================================================

variable "resource_lock" {
  description = "'None', 'CanNotDelete', or 'ReadOnly'."
  type        = string
  default     = "None"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID for diagnostic settings."
  type        = string
  default     = ""
}

variable "enable_boot_diagnostics" {
  description = "Enable boot diagnostics with managed storage."
  type        = bool
  default     = true
}

variable "enable_telemetry" {
  description = "Send anonymous AVM usage telemetry to Microsoft."
  type        = bool
  default     = true
}
