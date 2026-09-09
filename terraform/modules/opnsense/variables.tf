variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "VM ID of the firewall. Keep it the lowest of all guests."
  type        = number
  default     = 100
}

variable "vm_name" {
  description = "VM name"
  type        = string
  default     = "opnsense-fw"
}

variable "iso_file_id" {
  description = "Proxmox volume ID of the OPNsense installer ISO"
  type        = string
}

# ---------------------------------------------------------------------------
# Interfaces
# ---------------------------------------------------------------------------
# NIC order is the whole point of this module: Proxmox maps net0..net3 to
# FreeBSD vtnet0..vtnet3 in order, and the OPNsense installer asks you to
# assign interfaces by those names. Appending a NIC is safe; reordering the
# blocks below silently rewires a running firewall.
#
#   net0 -> vtnet0 -> WAN
#   net1 -> vtnet1 -> LAN
#   net2 -> vtnet2 -> DMZ
#   net3 -> vtnet3 -> LAB
#
variable "wan_bridge" {
  description = "Bridge carrying the WAN leg - the bridge with the physical NIC"
  type        = string
  default     = "vmbr0"
}

variable "lan_bridge" {
  description = "Bridge for trusted guests"
  type        = string
  default     = "vmbr1"
}

variable "dmz_bridge" {
  description = "Bridge for internet-facing services and cloudflared"
  type        = string
  default     = "vmbr2"
}

variable "lab_bridge" {
  description = "Bridge for experiments and quarantine"
  type        = string
  default     = "vmbr3"
}

variable "wan_mac_address" {
  description = <<-EOT
    MAC address of the WAN interface. Pinned so the home router hands out (or
    reserves) the same address across rebuilds, and so OPNsense keeps seeing
    the same interface. Locally administered range (02:...).
  EOT
  type        = string
  default     = "02:7A:AA:5D:AD:51"
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------
variable "cores" {
  description = "vCPU cores. Suricata and Zenarmor are the hungry parts."
  type        = number
  default     = 4
}

variable "memory" {
  description = <<-EOT
    RAM in MB. 2048 runs a plain router. Raise to 8192 before enabling
    Zenarmor + Suricata + Insight together, or reporting will OOM.
  EOT
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk in GB. Insight/Zenarmor keep flow history here."
  type        = number
  default     = 40
}

variable "datastore_id" {
  description = "Proxmox datastore for the OS disk"
  type        = string
  default     = "local-lvm"
}

variable "cpu_type" {
  description = <<-EOT
    'host' passes AES-NI etc. straight through, which FreeBSD and IPsec want.
    Only downside is live migration between dissimilar hosts - irrelevant on a
    single node.
  EOT
  type        = string
  default     = "host"
}

variable "startup_order" {
  description = "Proxmox boot order. 1 = before every other guest."
  type        = number
  default     = 1
}

variable "startup_up_delay" {
  description = "Seconds Proxmox waits after this VM before starting the next one, so guests do not come up without a gateway"
  type        = number
  default     = 45
}

variable "started" {
  description = "Whether Terraform keeps the VM running"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Proxmox tags"
  type        = list(string)
  default     = ["firewall", "opnsense", "terraform"]
}
