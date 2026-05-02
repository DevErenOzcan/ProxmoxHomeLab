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

variable "router_template_id" {
  description = "Kullanılacak router template ID'si (Örn: 900)"
  type        = number
}

variable "wan_mac_address" {
  description = "Modem tarafında 192.168.1.200 IP'sine sabitlenecek MAC adresi"
  type        = string
}