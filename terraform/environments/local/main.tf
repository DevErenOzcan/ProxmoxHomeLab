# ==========================================
# ISO DOWNLOADS
# ==========================================

# Router (OPNsense) ISO - reliable mirror
resource "proxmox_virtual_environment_download_file" "router_iso" {
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = var.node_name
  url                     = "https://frafiles.pfsense.org/mirror/downloads/pfSense-CE-2.7.2-RELEASE-amd64.iso.gz"
  file_name               = "pfsense-2.7.2-installer.iso"
  decompression_algorithm = "gz" # Proxmox understands "gz" and extracts it automatically
  upload_timeout          = 3600    # 1 hour timeout
}

# Ubuntu Server ISO
resource "proxmox_virtual_environment_download_file" "ubuntu_server_iso" {
  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
  file_name      = "ubuntu-26.04-live-server-amd64.iso"
  upload_timeout = 3600 # 1 hour timeout
}

# Ubuntu Desktop ISO
resource "proxmox_virtual_environment_download_file" "ubuntu_desktop_iso" {
  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = "https://releases.ubuntu.com/26.04/ubuntu-26.04-desktop-amd64.iso"
  file_name      = "ubuntu-26.04-desktop-amd64.iso"
  upload_timeout = 7200 # The desktop ISO is large (5GB+), give it 2 hours
}

# VirtIO driver ISO (needed so the Windows installer sees the disks)
resource "proxmox_virtual_environment_download_file" "virtio_iso" {
  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"
  file_name      = "virtio-win.iso"
  upload_timeout = 3600
}

# Windows 11 ISO
resource "proxmox_virtual_environment_download_file" "windows_11_iso" {
  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  # NOTE: download links from Microsoft expire within 24 hours.
  # If this fails, get a fresh link from Microsoft and update the URL below.
  url            = "https://software-static.download.prss.microsoft.com/dbazure/988969d5-f34g.../22631.2428.231001-0608.23h2_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_en-us.iso" # REPLACE THIS WITH YOUR OWN CURRENT LINK
  file_name      = "windows-11-installer.iso"
  upload_timeout = 7200 # The Windows ISO is large too, 2 hours
}


# ==========================================
# VIRTUAL MACHINE MODULES
# ==========================================

# The heart of the network: router module
module "network_router" {
  source             = "../../modules/router"
  proxmox_node       = var.node_name
  vm_id              = 100
  wan_mac_address    = "02:7A:AA:5D:AD:51"
  iso_file_id        = proxmox_virtual_environment_download_file.router_iso.id
}

# Server machine (Ubuntu)
module "ubuntu_server_vm" {
  source         = "../../modules/ubuntu_server"
  node_name      = var.node_name
  vm_id          = 101
  vm_name        = "ubuntu_server"
  ip_address     = "192.168.3.10/24"
  gateway        = "192.168.3.1" # This gateway IP must be assigned to the pfSense/OPNsense LAN interface
  network_bridge = "vmbr1"
  iso_file_id    = proxmox_virtual_environment_download_file.ubuntu_server_iso.id
  depends_on     = [module.network_router]
}

# Desktop machine (Ubuntu)
module "ubuntu_desktop_vm" {
  source         = "../../modules/ubuntu_desktop"
  node_name      = var.node_name
  vm_id          = 102
  vm_name        = "ubuntu_desktop"
  ip_address     = "192.168.3.11/24"
  gateway        = "192.168.3.1" # This gateway IP must be assigned to the pfSense/OPNsense LAN interface
  network_bridge = "vmbr1"
  iso_file_id    = proxmox_virtual_environment_download_file.ubuntu_desktop_iso.id
  depends_on     = [module.network_router]
}

# Desktop machine (Windows 11)
module "windows_11_vm" {
  source             = "../../modules/windows_11"
  node_name          = var.node_name
  vm_id              = 103
  vm_name            = "windows_11_desktop"
  ip_address         = "192.168.3.12/24"
  gateway            = "192.168.3.1" # This gateway IP must be assigned to the pfSense/OPNsense LAN interface
  network_bridge     = "vmbr1"
  iso_file_id        = proxmox_virtual_environment_download_file.windows_11_iso.id
  virtio_iso_file_id = proxmox_virtual_environment_download_file.virtio_iso.id
  depends_on         = [module.network_router]
}