module "vm" {
  source = "./modules/vm-wrapper"

  # ---- Naming ----
  workload_name   = var.workload_name
  environment     = var.environment
  location        = var.location
  instance_number = var.instance_number
  name_override   = var.name_override

  # ---- Placement ----
  resource_group_name = var.resource_group_name
  availability_zone   = var.availability_zone

  # ---- VM spec ----
  os_type                = var.os_type
  vm_size                = var.vm_size
  source_image_reference = var.source_image_reference

  # ---- Credentials ----
  admin_username = var.admin_username
  admin_password = var.admin_password

  # ---- Networking ----
  subnet_id = var.subnet_id

  # ---- Disks ----
  os_disk_size_gb              = var.os_disk_size_gb
  os_disk_storage_account_type = var.os_disk_storage_account_type
  data_disks                   = var.data_disks

  # ---- Linux ----
  disable_password_authentication = var.disable_password_authentication
  ssh_public_keys                 = var.ssh_public_keys

  # ---- Windows ----
  windows_patch_mode = var.windows_patch_mode
  computer_name      = var.computer_name
  time_zone          = var.time_zone
  license_type       = var.license_type

  # ---- Linux patch ----
  linux_patch_mode = var.linux_patch_mode

  # ---- Tags ----
  mandatory_tags  = var.mandatory_tags
  additional_tags = var.additional_tags

  # ---- Extensions ----
  enable_azure_monitor_agent   = var.enable_azure_monitor_agent
  enable_dependency_agent      = var.enable_dependency_agent
  enable_network_watcher_agent = var.enable_network_watcher_agent
  enable_antimalware           = var.enable_antimalware
  enable_entra_id_join         = var.enable_entra_id_join

  # ---- Governance ----
  resource_lock              = var.resource_lock
  log_analytics_workspace_id = var.log_analytics_workspace_id
  enable_boot_diagnostics    = var.enable_boot_diagnostics
  enable_telemetry           = var.enable_telemetry
}
