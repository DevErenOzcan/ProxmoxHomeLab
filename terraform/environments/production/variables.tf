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
    on desktop_datastore; its persistent data disk is data_disks["102"].
  EOT
  default     = true
}

variable "data_disks" {
  type        = map(number)
  description = <<-EOT
    Persistent data disks on the "vmdata" storage (the host's second NVMe,
    thick LVM): VM ID => size in GB. Each one is owned by a holder VM with ID
    9000 + the VM's ID (modules/data_disk), so the VM itself can be destroyed
    and rebuilt without losing it, and only that VM attaches it. To give a VM
    a disk, add a line here and pass module.data_disk["<id>"].disk to the VM.
    Sizes are reserved in full and must not change afterwards.
  EOT
  default = {
    "102" = 200 # ubuntu-desktop: /home
    "110" = 50  # dmz-docker: Docker's data-root and the compose projects
  }
}

variable "ssh_public_keys" {
  type        = list(string)
  description = <<-EOT
    Public keys cloud-init installs for the "ubuntu" user of every
    modules/ubuntu_server guest. The controller's key (WSL
    ~/.ssh/id_ed25519.pub), the same one ansible uses everywhere.
  EOT
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMCdb2x7BVEHm0qXNTy2RiEHRV+osCiw7DS5eBQD+yXE ansible-wsl",
  ]
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

# ---------------------------------------------------------------------------
# Server image
# ---------------------------------------------------------------------------
variable "ubuntu_server_image_url" {
  type        = string
  description = <<-EOT
    Ubuntu Server 26.04 (resolute) cloud image, pinned to one build. Bump the
    URL and ubuntu_server_image_sha256 together; the checksum is in
    SHA256SUMS in the same directory.
  EOT
  default     = "https://cloud-images.ubuntu.com/releases/resolute/release-20260927/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "ubuntu_server_image_sha256" {
  type        = string
  description = "SHA256 checksum for the cloud image"
  default     = "8800651811af9a85465ad1d552add729947bb16488dddb4a9b5305a3d97332b2"
}


