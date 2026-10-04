variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "VM ID"
  type        = number
}

variable "vm_name" {
  description = "VM name, also the guest's hostname (cloud-init)"
  type        = string
}

variable "description" {
  description = "Shown in the Proxmox GUI"
  type        = string
  default     = "Ubuntu Server from the cloud image. Managed by Terraform."
}

variable "image_file_id" {
  description = "Proxmox file ID of the cloud image the OS disk is imported from"
  type        = string
}

# ---------------------------------------------------------------------------
# Network (cloud-init)
# ---------------------------------------------------------------------------
variable "network_bridge" {
  description = "Bridge to attach to"
  type        = string
}

variable "ipv4_address" {
  description = "Static address with prefix length, e.g. 10.10.20.10/24"
  type        = string
}

variable "ipv4_gateway" {
  description = "Default gateway: the firewall's address on the segment"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers; the firewall's address on the segment answers (Unbound)"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Access (cloud-init)
# ---------------------------------------------------------------------------
variable "username" {
  description = "The default user cloud-init creates, with passwordless sudo and no password"
  type        = string
  default     = "ubuntu"
}

variable "ssh_public_keys" {
  description = "Public keys that may log in as username"
  type        = list(string)
}

# ---------------------------------------------------------------------------
# Sizing and storage
# ---------------------------------------------------------------------------
variable "datastore_id" {
  description = "Datastore for the OS disk and the cloud-init drive"
  type        = string
  default     = "local-lvm"
}

variable "cores" {
  description = "vCPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 2048
}

variable "disk_size" {
  description = "OS disk in GB; the cloud image is grown to this on first boot"
  type        = number
  default     = 20
}

variable "data_disk" {
  description = <<-EOT
    The persistent data disk attached as scsi1: the `disk` output of a
    modules/data_disk holder, which owns it, so this VM can be destroyed and
    rebuilt without losing it. null: no data disk.
  EOT
  type = object({
    datastore_id      = string
    path_in_datastore = string
    file_format       = string
    size              = number
  })
  default = null
}

variable "cpu_type" {
  description = "'host' passes the real CPU through; the guest never migrates"
  type        = string
  default     = "host"
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------
variable "started" {
  description = "Whether Terraform keeps the VM running"
  type        = bool
  default     = true
}

variable "on_boot" {
  description = "Start with the host"
  type        = bool
  default     = true
}

variable "startup_order" {
  description = "Proxmox boot order. The firewall is 1."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Proxmox tags"
  type        = list(string)
  default     = ["ubuntu", "terraform"]
}
