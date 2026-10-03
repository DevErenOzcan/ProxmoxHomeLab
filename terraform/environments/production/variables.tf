# ---------------------------------------------------------------------------
# Proxmox connection
# ---------------------------------------------------------------------------
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint. Default points to the host IP."
  default     = "https://192.168.1.200:8006/"
}

variable "proxmox_username" {
  type        = string
  description = "Proxmox node user"
  default     = "root@pam"
}

variable "proxmox_password" {
  type        = string
  description = "Proxmox node password. Pass it via TF_VAR_proxmox_password or a .tfvars file kept out of git."
  sensitive   = true
}

variable "node_name" {
  type        = string
  description = "Name of the Proxmox node guests are created on"
  default     = "proxmox"
}

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------
variable "opnsense_version" {
  type        = string
  description = "OPNsense release. Bump together with opnsense_iso_sha256."
  default     = "26.7"
}

variable "opnsense_mirror" {
  type        = string
  description = "OPNsense mirror base URL, without a trailing slash"
  default     = "https://mirrors.dotsrc.org/opnsense/releases"
}

variable "opnsense_iso_sha256" {
  type        = string
  description = <<-EOT
    SHA256 of the COMPRESSED installer (the .iso.bz2), because Proxmox verifies
    the download before decompressing it. Taken from
    OPNsense-<version>-checksums-amd64.sha256 on the mirror.
  EOT
  default     = "95cafedda6d5b22ce832e249dc2309110fbee19f813ad78cf28bb3d387186bfb"
}

variable "firewall_wan_connected" {
  type        = bool
  description = <<-EOT
    Connect the firewall's WAN interface to vmbr0. True because the firewall
    is installed and its WAN is 192.168.1.201 - false here would unplug the
    running firewall on the next apply.

    REINSTALLING? Pass -var firewall_wan_connected=false until the console
    shows WAN on 192.168.1.201: a fresh OPNsense comes up as 192.168.1.1/24
    with a DHCP server, which on this home network means it impersonates the
    router and takes the house offline (2026-09-09).
  EOT
  default     = true
}

# ---------------------------------------------------------------------------
# Guests
# ---------------------------------------------------------------------------
variable "create_desktop" {
  type        = bool
  description = <<-EOT
    Create the GPU-passthrough desktop workstation (VM 102). Its OS disk lives
    on desktop_datastore; its data disk is the whole of the host's nvme0n1,
    passed through - see modules/ubuntu_desktop.
  EOT
  default     = true
}

variable "desktop_datastore" {
  type        = string
  description = "Datastore for the workstation's OS and EFI disks"
  default     = "local-lvm"
}

variable "desktop_mac_address" {
  type        = string
  description = "Pinned MAC, so OPNsense can hold a DHCP reservation for 10.10.10.11"
  default     = "BC:24:11:B8:0E:F8"
}

# ---------------------------------------------------------------------------
# Desktop image
# ---------------------------------------------------------------------------
variable "ubuntu_desktop_qcow2_url" {
  type        = string
  description = <<-EOT
    Ubuntu Desktop pre-built qcow2 image from linuxcontainers.org - Ubuntu
    24.04 (noble) despite the "26.04" in the stored file name. VM 102 was
    built from this exact build; the guest's own changes on top of it are
    ansible/playbooks/ubuntu_desktop.
  EOT
  default     = "https://images.linuxcontainers.org/images/ubuntu/noble/amd64/desktop/20260912_07:42/disk.qcow2"
}

variable "ubuntu_desktop_qcow2_sha256" {
  type        = string
  description = "SHA256 checksum for the qcow2 image"
  default     = "14bdc8f2f3fd6b964b3932507611dd00ab45570b9860e7ce9e02d83d049b20af"
}


