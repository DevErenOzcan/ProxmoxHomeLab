# ============================================================================
# INSTALLER MEDIA AND DISK IMAGES
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
  url                     = "${var.opnsense_mirror}/${var.opnsense_version}/OPNsense-${var.opnsense_version}-vga-amd64.img.bz2"
  file_name               = "opnsense-${var.opnsense_version}-vga-amd64.img"
  checksum                = var.opnsense_iso_sha256
  checksum_algorithm      = "sha256"
  decompression_algorithm = "bz2"
  upload_timeout          = 1800

  # With overwrite = true (the provider default) every plan wants to replace
  # this resource: the decompressed size cannot be predicted, so "size" comes
  # out as (known after apply), and size forces replacement. That means
  # re-downloading 2 GB on every apply -- and deleting the ISO out from under
  # the running firewall VM, which has it attached as a CD.
  overwrite = false
}

# ---------------------------------------------------------------------------
# Ubuntu cloud image - the disk the Linux guests boot from
# ---------------------------------------------------------------------------
# This is a disk image, not an installer. It boots straight to a login prompt
# with cloud-init already applied, which is what makes the static addresses in
# locals.tf actually take effect.
#
# Two details that will bite if changed carelessly:
#
#   * The file is named .qcow2, not .img. Proxmox only accepts
#     ova|ovf|qcow2|raw|vmdk for the "import" content type, and Ubuntu's .img
#     really is a qcow2 (its header starts with QFI\xfb), so this renames it to
#     the truth rather than working around a check.
#   * The URL pins a dated build. The floating .../release/ path would start
#     serving a new image the moment Canonical publishes one, and the download
#     would then fail its checksum. Bump both together.
resource "proxmox_download_file" "ubuntu_cloud_image" {
  count = var.create_guests ? 1 : 0

  content_type       = "import"
  datastore_id       = "local"
  node_name          = var.node_name
  url                = var.ubuntu_cloud_image_url
  file_name          = var.ubuntu_cloud_image_file_name
  checksum           = var.ubuntu_cloud_image_sha256
  checksum_algorithm = "sha256"
  upload_timeout     = 1800
}

# ---------------------------------------------------------------------------
# Desktop workstation media
# ---------------------------------------------------------------------------
# The desktop VM is a GPU-passthrough workstation, so it gets a real installer
# and a real screen rather than a cloud image. Gated separately - see vms.tf.
resource "proxmox_download_file" "ubuntu_desktop_qcow2" {
  count = var.create_desktop ? 1 : 0

  content_type       = "import"
  datastore_id       = "local"
  node_name          = var.node_name
  url                = var.ubuntu_desktop_qcow2_url
  file_name          = "ubuntu-desktop-26.04-amd64.qcow2"
  checksum           = var.ubuntu_desktop_qcow2_sha256
  checksum_algorithm = "sha256"
  upload_timeout     = 7200
}

# ---------------------------------------------------------------------------
# Windows
# ---------------------------------------------------------------------------
# Microsoft's evaluation links expire ~24h after they are generated, so there
# is no usable default. Leave var.windows_11_iso_url empty and both of these
# are skipped along with the guest itself.
resource "proxmox_download_file" "virtio_iso" {
  count = var.windows_11_iso_url != "" ? 1 : 0

  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = var.virtio_iso_url
  file_name      = "virtio-win.iso"
  upload_timeout = 3600
}

resource "proxmox_download_file" "windows_11_iso" {
  count = var.windows_11_iso_url != "" ? 1 : 0

  content_type   = "iso"
  datastore_id   = "local"
  node_name      = var.node_name
  url            = var.windows_11_iso_url
  file_name      = "windows-11-installer.iso"
  upload_timeout = 7200
}
