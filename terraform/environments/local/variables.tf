variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint (Örn: https://192.168.1.100:8006/)"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox node kullanıcısı (Örn: root@pam)"
  default     = "root@pam"
}

variable "proxmox_password" {
  type        = string
  description = "Proxmox node şifresi (Uyarı: .tfvars içerisinde verin ve git'e eklemeyin)"
  sensitive   = true
}

variable "node_name" {
  type        = string
  description = "Sanal makinelerin kurulacağı Proxmox Node adı"
  default     = "pve"
}
