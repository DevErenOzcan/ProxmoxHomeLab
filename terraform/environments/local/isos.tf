# ============================================================================
# INSTALLER MEDIA
# ============================================================================
# Resource name note: the provider renamed proxmox_virtual_environment_download_file
# to proxmox_download_file ahead of its v1.0; the old name still works but warns.
# proxmox_virtual_environment_vm is NOT deprecated, so guests keep that name.
#
# Proxmox itself does the downloading, so the bytes never travel through this
# machine. Checksums are verified on the file as downloaded, i.e. BEFORE
# decompression - so a .bz2 URL needs the .bz2 checksum, not the ISO's.

# ---------------------------------------------------------------------------
# OPNsense - the firewall
# ---------------------------------------------------------------------------
# Replaces the old pfSense CE 2.7.2 download, whose mirror URL no longer
# resolves. Bump both the version and the checksum together; the checksum
# lives in OPNsense-<ver>-checksums-amd64.sha256 on the same mirror.
resource "proxmox_download_file" "opnsense_iso" {
  content_type            = "iso"
  datastore_id            = "local"
  node_name               = var.node_name
  url                     = "${var.opnsense_mirror}/${var.opnsense_version}/OPNsense-${var.opnsense_version}-dvd-amd64.iso.bz2"
  file_name               = "opnsense-${var.opnsense_version}-dvd-amd64.iso"
  checksum                = var.opnsense_iso_sha256
  checksum_algorithm      = "sha256"
  decompression_algorithm = "bz2"
  upload_timeout          = 1800
}

# ---------------------------------------------------------------------------
# Guest operating systems
# ---------------------------------------------------------------------------
# Gated on var.create_guests so the first apply brings up only the firewall.
# Nothing else can reach the network until OPNsense is installed anyway.

resource "proxmox_download_file" "ubuntu_server_iso" {
  count = var.create_guests ? 1 : 0

  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = var.ubuntu_server_iso_url
  file_name      = "ubuntu-server-amd64.iso"
  upload_timeout = 3600
}

resource "proxmox_download_file" "ubuntu_desktop_iso" {
  count = var.create_guests ? 1 : 0

  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = var.ubuntu_desktop_iso_url
  file_name      = "ubuntu-desktop-amd64.iso"
  upload_timeout = 7200
}

resource "proxmox_download_file" "virtio_iso" {
  count = var.create_guests ? 1 : 0

  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = var.virtio_iso_url
  file_name      = "virtio-win.iso"
  upload_timeout = 3600
}

# Microsoft's evaluation links expire ~24h after they are generated, so there
# is no usable default. Leave var.windows_11_iso_url empty and this is skipped;
# set it to a fresh link when you actually want the Windows guest.
resource "proxmox_download_file" "windows_11_iso" {
  count = var.create_guests && var.windows_11_iso_url != "" ? 1 : 0

  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = var.windows_11_iso_url
  file_name      = "windows-11-installer.iso"
  upload_timeout = 7200
}
