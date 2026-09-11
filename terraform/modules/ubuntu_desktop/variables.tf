variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "VM ID"
  type        = number
}

variable "vm_name" {
  description = "VM name"
  type        = string
  default     = "ubuntu-desktop"
}

variable "iso_file_id" {
  description = "Ubuntu Desktop installer ISO. A real install, not a cloud image - this machine has a screen."
  type        = string
}

variable "network_bridge" {
  description = "Bridge to attach to"
  type        = string
  default     = "vmbr1"
}

variable "mac_address" {
  description = <<-EOT
    Pinned so OPNsense can hold a DHCP reservation for it. That is how this VM
    gets 10.10.10.11 - there is no cloud-init here to set an address, because
    an installer ISO carries none.
  EOT
  type        = string
  default     = "BC:24:11:B8:0E:F8"
}

# ---------------------------------------------------------------------------
# Sizing and storage
# ---------------------------------------------------------------------------
variable "datastore_id" {
  description = <<-EOT
    Datastore for the OS and EFI disks. Defaults to nvme2, the thin pool the
    pve_storage Ansible role builds out of the reclaimed nvme0n1. Terraform
    will fail with "storage 'nvme2' does not exist" until that has run.
  EOT
  type        = string
  default     = "nvme2"
}

variable "cores" {
  description = "vCPU cores"
  type        = number
  default     = 12
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 16384
}

variable "disk_size" {
  description = "OS Disk in GB"
  type        = number
  default     = 40
}

variable "data_volume_id" {
  description = "ID of the independent data volume to attach (e.g. local-lvm:vm-999-disk-1). If empty, no data volume is attached."
  type        = string
  default     = ""
}

variable "data_disk_size" {
  description = "Size of the data disk in GB. Must match the actual size of the independent volume."
  type        = number
  default     = 300
}

variable "cpu_type" {
  description = "'host' is required for passthrough to behave"
  type        = string
  default     = "host"
}

# ---------------------------------------------------------------------------
# Passthrough
# ---------------------------------------------------------------------------
variable "hostpci_devices" {
  description = <<-EOT
    PCI devices handed to the guest, in order. Kept exactly as this lab had
    them. Notes on the two that look odd but are not:

      * "0000:01:00" has no function number on purpose - Proxmox reads that as
        "every function of that device", which is valid and verified against
        this host's parser.
      * 0000:06:00.2 is the AMD Platform Security Processor rather than a GPU
        function. It sits alone in IOMMU group 18 so it is not forced along by
        grouping, and passing it is unusual - but it is what this lab ran, so
        it stays. Drop it here if the guest ever misbehaves around it.

    xvga marks the primary display adapter; exactly one device may set it.
  EOT
  type = list(object({
    device = string
    pcie   = optional(bool, true)
    xvga   = optional(bool, false)
  }))
  default = [
    { device = "0000:06:00.0", xvga = true }, # AMD Cezanne iGPU - drives the panel
    { device = "0000:01:00" },                # NVIDIA RTX 3050 Ti, all functions
    { device = "0000:06:00.1" },              # Renoir HD Audio
    { device = "0000:06:00.2" },              # Platform Security Processor
    { device = "0000:06:00.5" },              # Audio coprocessor
    { device = "0000:06:00.6" },              # HD Audio controller
    { device = "0000:03:00.0" },              # MediaTek MT7921 wireless
  ]
}

variable "usb_ports" {
  description = <<-EOT
    USB host ports handed to the guest. The previous list also named 1-2 and
    3-2, which do not exist on this machine - Proxmox fails the start rather
    than ignoring them. What is actually there:

      1-3  integrated camera        1-4  bluetooth
      3-3  ITE controller (8295)    3-4  ITE controller (8176)

    The ITE devices are the built-in keyboard and touchpad, so handing them
    over means the laptop's own keyboard types into this guest, not the host.
  EOT
  type        = list(string)
  default     = ["1-3", "1-4", "3-3", "3-4"]
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
  description = <<-EOT
    Start with the host. Off by default: this VM seizes the GPUs and the
    keyboard, which is a surprising thing for a reboot to do on its own.
  EOT
  type        = bool
  default     = false
}

variable "startup_order" {
  description = "Proxmox boot order. The firewall is 1."
  type        = number
  default     = 2
}

variable "tags" {
  description = "Proxmox tags"
  type        = list(string)
  default     = ["ubuntu", "desktop", "passthrough", "terraform"]
}
