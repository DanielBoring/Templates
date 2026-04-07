output "vm_id" {
  description = "The resource ID of the virtual machine."
  value       = module.vm.vm_id
}

output "vm_name" {
  description = "The name of the virtual machine."
  value       = module.vm.vm_name
}

output "private_ip_address" {
  description = "The primary private IP address assigned to the VM's NIC."
  value       = module.vm.private_ip_address
}

output "system_assigned_identity_principal_id" {
  description = "The principal ID of the system-assigned managed identity. Use to grant RBAC on other resources (e.g. Key Vault, Storage)."
  value       = module.vm.system_assigned_identity_principal_id
}
