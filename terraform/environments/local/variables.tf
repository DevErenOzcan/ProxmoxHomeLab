variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint (e.g. https://192.168.1.100:8006/)"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox node user (e.g. root@pam)"
  default     = "root@pam"
}

variable "proxmox_password" {
  type        = string
  description = "Proxmox node password (pass it via .tfvars and keep that out of git)"
  sensitive   = true
}

variable "node_name" {
  type        = string
  description = "Name of the Proxmox node the virtual machines are created on"
  default     = "proxmox"
}
