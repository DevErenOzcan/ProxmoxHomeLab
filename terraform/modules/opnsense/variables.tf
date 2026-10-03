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

variable "cdrom_interface" {
  description = <<-EOT
    Which IDE/SATA slot the installer ISO occupies. Pinned rather than left to
    the provider because boot_order has to name it; see the boot_order comment
    in main.tf.
  EOT
  type        = string
  default     = "ide2"
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

variable "wan_connected" {
  description = <<-EOT
    Plug the WAN interface into the home network. Keep this false until
    OPNsense has been installed AND its interfaces assigned from the console.

    A fresh OPNsense applies a factory config of LAN = 192.168.1.1/24 with a
    DHCP server. If that lands on a bridge carrying a 192.168.1.0/24 home
    network, the VM starts answering for the real router and serving its own
    leases -- the whole house loses internet, not just the lab. Booting with
    the cable unplugged makes that impossible rather than merely unlikely.
  EOT
  type        = bool
  default     = false
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

# The internal legs were left to Proxmox's random BC:24:11 MACs when the VM
# was created; these are the addresses it ended up with. Pinned so a rebuilt VM
# presents the same hardware to OPNsense and to anything caching ARP.
variable "lan_mac_address" {
  description = "MAC address of net1 (vtnet1, LAN)"
  type        = string
  default     = "BC:24:11:40:72:AD"
}

variable "dmz_mac_address" {
  description = "MAC address of net2 (vtnet2, DMZ)"
  type        = string
  default     = "BC:24:11:97:40:B5"
}

variable "lab_mac_address" {
  description = "MAC address of net3 (vtnet3, LAB)"
  type        = string
  default     = "BC:24:11:46:18:20"
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------
variable "cores" {
  description = <<-EOT
    vCPU cores. 2 is what the running firewall has. Suricata and Zenarmor are
    the hungry parts if they are ever turned on.
  EOT
  type        = number
  default     = 2
}

variable "memory" {
  description = <<-EOT
    RAM in MB. 2048 runs a plain router, which is what this is. Raise to 8192
    before enabling Zenarmor + Suricata + Insight together, or reporting will
    OOM.
  EOT
  type        = number
  default     = 2048
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
