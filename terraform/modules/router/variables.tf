variable "proxmox_node" {
  description = "Proxmox node adı"
  type        = string
}

variable "vm_id" {
  description = "Router sanal makinesinin ID'si"
  type        = number
}

variable "router_name" {
  description = "Router sanal makinesinin adı"
  type        = string
  default     = "pfsense-router"
}

variable "wan_mac_address" {
  description = "Modem tarafında 192.168.1.200 IP'sine sabitlenecek MAC adresi"
  type        = string
}

variable "iso_file_id" {
  description = "Kurulum için Terraform tarafından indirilen ISO dosyasının ID'si"
  type        = string
}