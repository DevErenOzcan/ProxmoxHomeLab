output "vm_id" {
  description = "VM ID of the firewall"
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}

output "vm_name" {
  description = "VM name of the firewall"
  value       = proxmox_virtual_environment_vm.opnsense.name
}

output "wan_mac_address" {
  description = "WAN MAC - use it for the DHCP reservation on the home router"
  value       = var.wan_mac_address
}

output "interface_map" {
  description = "Which FreeBSD interface lands on which bridge. The OPNsense installer asks for exactly this."
  value = {
    vtnet0 = { role = "WAN", bridge = var.wan_bridge }
    vtnet1 = { role = "LAN", bridge = var.lan_bridge }
    vtnet2 = { role = "DMZ", bridge = var.dmz_bridge }
    vtnet3 = { role = "LAB", bridge = var.lab_bridge }
  }
}
