# ---------------------------------------------------------------------------
# Proxmox connection
# ---------------------------------------------------------------------------
variable "proxmox_endpoint" {
  type        = string
  description = "Proxmox API endpoint. run_vms.sh sets this to https://127.0.0.1:8006/ because it runs on the host itself."
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

variable "firewall_cores" {
  type        = number
  description = "vCPU cores for OPNsense"
  default     = 4
}

variable "firewall_memory" {
  type        = number
  description = "RAM in MB for OPNsense. Raise to 8192 before turning on Zenarmor + Suricata + Insight together."
  default     = 4096
}

# ---------------------------------------------------------------------------
# Guests
# ---------------------------------------------------------------------------
variable "create_guests" {
  type        = bool
  description = <<-EOT
    Create the guest VMs. Leave false until OPNsense is installed and its LAN
    interface answers on 10.10.10.1 - guests brought up before that have no
    gateway. Then: terraform apply -var create_guests=true
  EOT
  default     = false
}

variable "ubuntu_server_iso_url" {
  type        = string
  description = "Ubuntu Server installer ISO URL"
  default     = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
}

variable "ubuntu_desktop_iso_url" {
  type        = string
  description = "Ubuntu Desktop installer ISO URL"
  default     = "https://releases.ubuntu.com/26.04/ubuntu-26.04-desktop-amd64.iso"
}

variable "virtio_iso_url" {
  type        = string
  description = "VirtIO driver ISO, needed for Windows to see its disk"
  default     = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
}

variable "windows_11_iso_url" {
  type        = string
  description = <<-EOT
    Windows 11 ISO URL. No default on purpose: Microsoft's evaluation links
    expire about 24 hours after they are generated, so a committed URL is
    always stale. Empty means "skip the Windows guest entirely".
  EOT
  default     = ""
}
