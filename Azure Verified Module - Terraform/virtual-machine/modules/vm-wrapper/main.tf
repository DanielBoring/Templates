# ============================================================
# vm-wrapper — org wrapper around the AVM VM module
#
# This module enforces organisation defaults:
#   - Auto-generated naming convention
#   - Mandatory tagging with three-layer merge
#   - Azure Monitor Agent on by default
#   - Boot diagnostics on by default
#   - Simplified NIC: provide a subnet_id, wrapper builds the NIC
#   - Auto-named OS and data disks
#   - OS/Linux branching handled internally
# ============================================================

locals {
  # ----------------------------------------------------------
  # Naming
  # ----------------------------------------------------------
  location_short_map = {
    eastus             = "eus"
    eastus2            = "eus2"
    westus             = "wus"
    westus2            = "wus2"
    westus3            = "wus3"
    centralus          = "cus"
    northcentralus     = "ncus"
    southcentralus     = "scus"
    westcentralus      = "wcus"
    australiaeast      = "aue"
    australiasoutheast = "ause"
    northeurope        = "neu"
    westeurope         = "weu"
    uksouth            = "uks"
    ukwest             = "ukw"
    eastasia           = "ea"
    southeastasia      = "sea"
    japaneast          = "jae"
    japanwest          = "jaw"
    canadacentral      = "cac"
    canadaeast         = "cae"
    brazilsouth        = "brs"
    southafricanorth   = "san"
    uaenorth           = "uaen"
  }

  location_short = lookup(local.location_short_map, lower(var.location), substr(lower(var.location), 0, 4))

  vm_name = var.name_override != "" ? var.name_override : "vm-${var.workload_name}-${var.environment}-${local.location_short}-${var.instance_number}"

  # ----------------------------------------------------------
  # Tags — three-layer merge: auto + mandatory + additional
  # ----------------------------------------------------------
  auto_tags = {
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
  merged_tags = merge(local.auto_tags, var.mandatory_tags, var.additional_tags)

  # ----------------------------------------------------------
  # Data disks — build AVM-compatible map from simplified list
  # ----------------------------------------------------------
  data_disk_map = {
    for idx, disk in var.data_disks :
    format("datadisk%02d", idx + 1) => {
      name                 = "${local.vm_name}-datadisk-${format("%02d", idx + 1)}"
      storage_account_type = disk.storage_account_type
      lun                  = disk.lun != null ? disk.lun : idx
      caching              = disk.caching
      disk_size_gb         = disk.disk_size_gb
      create_option        = "Empty"
    }
  }

  # ----------------------------------------------------------
  # Managed identity
  # AMA requires system-assigned identity to authenticate to
  # Azure Monitor. Enable automatically when AMA is on.
  # ----------------------------------------------------------
  needs_system_identity = var.enable_azure_monitor_agent

  # ----------------------------------------------------------
  # Extensions — build per-OS, then merge
  # ----------------------------------------------------------

  # Azure Monitor Agent
  ama_extension_name = "AzureMonitor${var.os_type}Agent"
  ama_extension = var.enable_azure_monitor_agent ? {
    (local.ama_extension_name) = {
      name                       = local.ama_extension_name
      publisher                  = "Microsoft.Azure.Monitor"
      type                       = local.ama_extension_name
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
      automatic_upgrade_enabled  = true
      settings                   = null
      protected_settings         = null
    }
  } : {}

  # Dependency Agent (requires AMA)
  dep_agent_type = var.os_type == "Windows" ? "DependencyAgentWindows" : "DependencyAgentLinux"
  dep_agent_extension = var.enable_dependency_agent && var.enable_azure_monitor_agent ? {
    (local.dep_agent_type) = {
      name                       = local.dep_agent_type
      publisher                  = "Microsoft.Azure.Monitoring.DependencyAgent"
      type                       = local.dep_agent_type
      type_handler_version       = "9.5"
      auto_upgrade_minor_version = true
      automatic_upgrade_enabled  = true
      settings                   = jsonencode({ enableAMA = true })
      protected_settings         = null
    }
  } : {}

  # Network Watcher Agent
  nw_agent_type = var.os_type == "Windows" ? "NetworkWatcherAgentWindows" : "NetworkWatcherAgentLinux"
  nw_extension = var.enable_network_watcher_agent ? {
    (local.nw_agent_type) = {
      name                       = local.nw_agent_type
      publisher                  = "Microsoft.Azure.NetworkWatcher"
      type                       = local.nw_agent_type
      type_handler_version       = "1.4"
      auto_upgrade_minor_version = true
      automatic_upgrade_enabled  = true
      settings                   = null
      protected_settings         = null
    }
  } : {}

  # Microsoft Antimalware (Windows only)
  antimalware_extension = var.enable_antimalware && var.os_type == "Windows" ? {
    IaaSAntimalware = {
      name                       = "IaaSAntimalware"
      publisher                  = "Microsoft.Azure.Security"
      type                       = "IaaSAntimalware"
      type_handler_version       = "1.3"
      auto_upgrade_minor_version = true
      automatic_upgrade_enabled  = false
      settings = jsonencode({
        AntimalwareEnabled = true
        RealtimeProtectionEnabled = "true"
        ScheduledScanSettings = {
          isEnabled = "true"
          scanType  = "Quick"
          day       = "7"
          time      = "120"
        }
        Exclusions = {
          Extensions = ""
          Paths      = ""
          Processes  = ""
        }
      })
      protected_settings = null
    }
  } : {}

  # Microsoft Entra ID Join
  entra_type = var.os_type == "Windows" ? "AADLoginForWindows" : "AADSSHLoginForLinux"
  entra_extension = var.enable_entra_id_join ? {
    (local.entra_type) = {
      name                       = local.entra_type
      publisher                  = "Microsoft.Azure.ActiveDirectory"
      type                       = local.entra_type
      type_handler_version       = "1.0"
      auto_upgrade_minor_version = true
      automatic_upgrade_enabled  = true
      settings                   = null
      protected_settings         = null
    }
  } : {}

  all_extensions = merge(
    local.ama_extension,
    local.dep_agent_extension,
    local.nw_extension,
    local.antimalware_extension,
    local.entra_extension
  )

  # ----------------------------------------------------------
  # Patch mode
  # ----------------------------------------------------------
  patch_mode = var.os_type == "Windows" ? var.windows_patch_mode : var.linux_patch_mode

  # ----------------------------------------------------------
  # Diagnostic settings
  # ----------------------------------------------------------
  diagnostic_settings = var.log_analytics_workspace_id != "" ? {
    workspace = {
      workspace_resource_id = var.log_analytics_workspace_id
    }
  } : {}
}

# ============================================================
# AVM — Azure/avm-res-compute-virtualmachine/azurerm
#
# Source: https://registry.terraform.io/modules/Azure/avm-res-compute-virtualmachine/azurerm
# Changelog: https://github.com/Azure/terraform-azurerm-avm-res-compute-virtualmachine/releases
#
# Version pin: update deliberately after reviewing the changelog.
# ============================================================
module "virtual_machine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "~> 0.17"

  # ---- Identity ----
  name                = local.vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = var.os_type
  sku_size            = var.vm_size

  # ---- Network ----
  # Wrapper builds a single primary NIC from a subnet ID.
  # To add additional NICs, extend this module.
  network_interfaces = {
    nic_primary = {
      name = "nic-${local.vm_name}-01"
      ip_configurations = {
        ipconfig_primary = {
          name                          = "ipconfig1"
          private_ip_subnet_resource_id = var.subnet_id
          is_primary_ipconfiguration    = true
        }
      }
    }
  }

  # ---- OS disk ----
  os_disk = {
    name                 = "${local.vm_name}-osdisk"
    caching              = "ReadWrite"
    storage_account_type = var.os_disk_storage_account_type
    disk_size_gb         = var.os_disk_size_gb > 0 ? var.os_disk_size_gb : null
  }

  # ---- Image ----
  source_image_reference = var.source_image_reference

  # ---- Credentials ----
  admin_username = var.admin_username
  admin_password = var.os_type == "Windows" ? var.admin_password : (var.disable_password_authentication ? null : var.admin_password)

  # Linux SSH keys
  admin_ssh_keys = var.os_type == "Linux" ? var.ssh_public_keys : []

  # ---- Zone ----
  zone = var.availability_zone

  # ---- Data disks ----
  data_disk_managed_disks = local.data_disk_map

  # ---- Identity ----
  managed_identities = local.needs_system_identity ? {
    system_assigned = true
  } : null

  # ---- Extensions ----
  extensions = local.all_extensions

  # ---- Boot diagnostics ----
  # An empty object enables boot diagnostics with Azure-managed storage.
  # null disables it entirely.
  boot_diagnostics = var.enable_boot_diagnostics ? {} : null

  # ---- Resource lock ----
  lock = var.resource_lock != "None" ? {
    kind = var.resource_lock
    name = "lock-${local.vm_name}"
  } : null

  # ---- Diagnostic settings ----
  diagnostic_settings = local.diagnostic_settings

  # ---- OS-specific ----
  patch_mode    = local.patch_mode
  computer_name = var.computer_name != "" ? var.computer_name : null
  timezone      = var.os_type == "Windows" && var.time_zone != "" ? var.time_zone : null
  license_type  = var.os_type == "Windows" && var.license_type != "" ? var.license_type : null

  disable_password_authentication = var.os_type == "Linux" ? var.disable_password_authentication : null

  # ---- Tags ----
  tags = local.merged_tags

  # ---- Telemetry ----
  enable_telemetry = var.enable_telemetry
}
