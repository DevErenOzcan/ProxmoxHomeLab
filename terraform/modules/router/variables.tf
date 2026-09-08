variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "ID of the router virtual machine"
  type        = number
}

variable "router_name" {
  description = "Name of the router virtual machine"
  type        = string
  default     = "pfsense-router"
}

variable "wan_mac_address" {
  description = "MAC address the modem pins to 192.168.1.200"
  type        = string
}

variable "iso_file_id" {
  description = "ID of the installer ISO downloaded by Terraform"
  type        = string
}