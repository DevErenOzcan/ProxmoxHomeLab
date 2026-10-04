variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "for_vm_id" {
  description = "VM ID of the VM that attaches this disk (for the description only)"
  type        = number
}

variable "vm_id" {
  description = "VM ID of the holder. Convention: 9000 + the ID of the VM that uses the disk."
  type        = number
}

variable "name" {
  description = "Name of the holder VM"
  type        = string
}

variable "size" {
  description = <<-EOT
    Size of the disk in GB. Reserved in full on thick-LVM storage. Choose it
    with room to grow: the provider's attached-disk pattern must not resize the
    disk afterwards.
  EOT
  type        = number
}

variable "datastore_id" {
  description = "Proxmox storage the disk is created on"
  type        = string
  default     = "vmdata"
}

variable "tags" {
  description = "Proxmox tags"
  type        = list(string)
  default     = ["data-disk", "terraform"]
}
