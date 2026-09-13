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
    Connect the firewall's WAN interface to vmbr0. Leave false for the install:
    a fresh OPNsense comes up as 192.168.1.1/24 with a DHCP server, which on
    this home network means it impersonates the router and takes the house
    offline. Flip to true once the console shows WAN on 192.168.1.201.
  EOT
  default     = false
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
    Create the cloud-image guests (currently ubuntu-server). On by default:
    they boot fine before OPNsense is configured, they just cannot reach
    anything until it is. Turn off with --no-guests on state_push_terraform.sh.
  EOT
  default     = true
}

variable "create_desktop" {
  type        = bool
  description = <<-EOT
    Create the GPU-passthrough desktop workstation. Needs storage "nvme2",
    which the pve_storage Ansible role builds from the reclaimed nvme0n1 -
    state_push_terraform.sh checks for it and says so if it is missing.
  EOT
  default     = true
}

variable "desktop_datastore" {
  type        = string
  description = "Datastore for the workstation's OS and EFI disks"
  default     = "local-lvm"
}

variable "desktop_cores" {
  type        = number
  description = "vCPU cores for the workstation"
  default     = 12
}

variable "desktop_memory" {
  type        = number
  description = <<-EOT
    RAM in MB for the workstation. 16 GB of the host's 19 GB, so this and
    ubuntu-server (8 GB) plus OPNsense (4 GB) over-commit - fine while they are
    not all busy, but do not start all three and expect headroom.
  EOT
  default     = 16384
}

variable "desktop_disk" {
  type        = number
  description = "Disk in GB for the workstation"
  default     = 40
}

variable "data_volume_id" {
  type        = string
  description = "Physical disk or Datastore ID for the data volume"
  default     = "/dev/nvme0n1"
}

variable "data_disk_size" {
  type        = number
  description = "Size of the data volume"
  default     = 500
}

variable "desktop_mac_address" {
  type        = string
  description = "Pinned MAC, so OPNsense can hold a DHCP reservation for 10.10.10.11"
  default     = "BC:24:11:B8:0E:F8"
}

# ---------------------------------------------------------------------------
# Ubuntu cloud image
# ---------------------------------------------------------------------------
variable "ubuntu_cloud_image_url" {
  type        = string
  description = <<-EOT
    Ubuntu cloud image. A dated build on purpose: the floating .../release/
    path starts serving a new image whenever Canonical publishes one, which
    would then fail the checksum below. Bump both together, from
    https://cloud-images.ubuntu.com/releases/26.04/
  EOT
  default     = "https://cloud-images.ubuntu.com/releases/26.04/release-20260823/ubuntu-26.04-server-cloudimg-amd64.img"
}

variable "ubuntu_cloud_image_file_name" {
  type        = string
  description = <<-EOT
    Stored name. Must end in .qcow2: Proxmox accepts only
    ova|ovf|qcow2|raw|vmdk for the "import" content type, and Canonical's .img
    is in fact a qcow2 file.
  EOT
  default     = "ubuntu-26.04-server-cloudimg-amd64.qcow2"
}

variable "ubuntu_cloud_image_sha256" {
  type        = string
  description = "From SHA256SUMS in the same directory as the image"
  default     = "8196be9d7958059cb56c6c75c80fdf6cee8a8885bc149ea791d7db1c7ef93035"
}

# ---------------------------------------------------------------------------
# Guest credentials
# ---------------------------------------------------------------------------
variable "guest_username" {
  type        = string
  description = "Cloud-init user created on the Linux guests"
  default     = "ubuntu"
}

variable "guest_password" {
  type        = string
  description = <<-EOT
    Password for that user. Empty means key-only, which is the better default
    as long as guest_ssh_public_key_files finds a key.
  EOT
  default     = ""
  sensitive   = true
}

variable "guest_ssh_public_key_files" {
  type        = list(string)
  description = <<-EOT
    Public keys to authorise, by path ON THE HOST - Terraform runs there.
    Missing files are skipped. The Proxmox node's own key is the default, so a
    fresh clone can always get into its guests from the host; add your laptop's
    key here (or run ./state_push_ansible.sh --install-key first and point at
    that) to reach them directly.
  EOT
  default     = [
    "/root/.ssh/id_rsa.pub",
    "/root/.ssh/id_ed25519.pub",
    "~/.ssh/id_rsa.pub",
    "~/.ssh/id_ed25519.pub"
  ]
}

# ---------------------------------------------------------------------------
# Guest sizing
# ---------------------------------------------------------------------------
variable "ubuntu_server_cores" {
  type        = number
  description = "vCPU cores for ubuntu-server"
  default     = 4
}

variable "ubuntu_server_memory" {
  type        = number
  description = <<-EOT
    RAM in MB for ubuntu-server. The host has 19 GB and OPNsense already holds
    4 GB, so 8 GB here still leaves room for the desktop workstation later.
  EOT
  default     = 8192
}

variable "ubuntu_server_disk" {
  type        = number
  description = "Disk in GB for ubuntu-server. Thin-provisioned, so it costs what it uses."
  default     = 120
}

variable "ubuntu_desktop_qcow2_url" {
  type        = string
  description = "Ubuntu Desktop pre-built qcow2 image from linuxcontainers.org"
  default     = "https://images.linuxcontainers.org/images/ubuntu/noble/amd64/desktop/20260912_07:42/disk.qcow2"
}

variable "ubuntu_desktop_qcow2_sha256" {
  type        = string
  description = "SHA256 checksum for the qcow2 image"
  default     = "14bdc8f2f3fd6b964b3932507611dd00ab45570b9860e7ce9e02d83d049b20af"
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
