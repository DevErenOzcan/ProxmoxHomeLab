variable "node_name" { type = string }
variable "vm_id" { type = number }
variable "vm_name" { type = string }
variable "ip_address" { type = string }
variable "gateway" { type = string, default = "192.168.3.1" }
variable "network_bridge" { type = string, default = "vmbr1" }
variable "iso_file_id" { type = string }
variable "virtio_iso_file_id" { type = string }