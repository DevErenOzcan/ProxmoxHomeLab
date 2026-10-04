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

variable "image_file_id" {
  description = "Proxmox file ID of the pre-built qcow2 disk image the OS disk is imported from"
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
    gets 10.10.10.11 - the image carries no cloud-init drive to set an
    address.
  EOT
  type        = string
  default     = "BC:24:11:B8:0E:F8"
}

# ---------------------------------------------------------------------------
# Sizing and storage
# ---------------------------------------------------------------------------
variable "datastore_id" {
  description = "Datastore for the OS and EFI disks"
  type        = string
  default     = "local-lvm"
}

variable "cores" {
  description = "vCPU cores"
  type        = number
  default     = 8
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 12 * 1024
}

variable "disk_size" {
  description = "OS Disk in GB"
  type        = number
  default     = 40
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
  description = "'host' passes the real CPU through, which passthrough guests want"
  type        = string
  default     = "host"
}

# ---------------------------------------------------------------------------
# Passthrough
# ---------------------------------------------------------------------------
variable "hostpci_devices" {
  description = <<-EOT
    PCI devices handed to the guest, in order (hostpci0, hostpci1, ...).
    Exactly what VM 102 runs: the Cezanne iGPU as the primary display and the
    RTX 3050 Ti. The other functions bound to vfio-pci on the host (iGPU
    audio, PSP, audio coprocessor, MT7921) are not passed to this guest.

    xvga marks the primary display adapter; exactly one device may set it.
  EOT
  type = list(object({
    device = string
    pcie   = optional(bool, false)
    xvga   = optional(bool, false)
  }))
  default = [
    { device = "0000:06:00.0", xvga = true }, # AMD Cezanne iGPU - drives the panel
    { device = "0000:01:00.0" },              # NVIDIA RTX 3050 Ti
  ]
}

variable "usb_ports" {
  description = <<-EOT
    USB host PORTS handed to the guest, in order (usb0, usb1, ...). These are
    ports, not devices: whatever is plugged in there belongs to the guest, and
    an empty port is fine. What sits on them as of 2026-10-03:

      1-2    (empty)                  1-3    integrated camera
      1-4    MediaTek bluetooth       3-3    ITE controller (8176)
      3-4    ITE controller (8295)    3-2    (empty)
      1-1.1  external hub, port 1     1-1.2  external hub, port 2 (G300 mouse)

    The ITE devices are the built-in keyboard and touchpad, so the laptop's
    own keyboard types into this guest, not the host. The rest of that hub is
    not passed through: 1-1.3 (card reader) and 1-1.4 (RTL8152 USB NIC, which
    the host sees as enx00e04c360130, down and unused).
  EOT
  type        = list(string)
  default     = ["1-2", "1-3", "1-4", "3-3", "3-4", "3-2", "1-1.1", "1-1.2"]
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
