output "vm_id" {
  description = "VM ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "vm_name" {
  description = "VM name"
  value       = proxmox_virtual_environment_vm.this.name
}

output "ip_address" {
  description = "Static address configured through cloud-init"
  value       = var.ip_address
}

output "login" {
  description = "How to get in once OPNsense is routing"
  value       = "ssh ${var.username}@${split("/", var.ip_address)[0]}"
}
