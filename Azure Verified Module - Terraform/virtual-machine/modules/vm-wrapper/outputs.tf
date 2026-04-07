output "vm_id" {
  description = "The resource ID of the virtual machine."
  value       = module.virtual_machine.resource_id
}

output "vm_name" {
  description = "The name of the virtual machine as deployed."
  value       = module.virtual_machine.name
}

output "private_ip_address" {
  description = "The primary private IP address of the VM's NIC."
  value       = module.virtual_machine.private_ip_addresses != null ? module.virtual_machine.private_ip_addresses[0] : null
}

output "system_assigned_identity_principal_id" {
  description = "The principal ID of the system-assigned managed identity. Null if identity was not enabled."
  value       = try(module.virtual_machine.system_assigned_mi_principal_id, null)
}
