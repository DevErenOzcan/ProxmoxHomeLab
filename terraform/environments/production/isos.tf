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
# Bump the version and the checksum together; the checksum lives in
# OPNsense-<ver>-checksums-amd64.sha256 on the same mirror.
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

  # With overwrite = true (the provider default) every plan wants to replace
  # this resource: the decompressed size cannot be predicted, so "size" comes
  # out as (known after apply), and size forces replacement. That means
  # re-downloading 2 GB on every apply -- and deleting the ISO out from under
  # the running firewall VM, which has it attached as a CD.
  overwrite = false
}

# ---------------------------------------------------------------------------
# Desktop workstation disk image
# ---------------------------------------------------------------------------
# A pre-built Ubuntu Desktop disk (linuxcontainers.org), imported as VM 102's
# OS disk. It carries no cloud-init, so the guest's address comes from an
# OPNsense DHCP reservation, not from Terraform. Gated by create_desktop.
#
# The "import" content type only accepts ova|ovf|qcow2|raw|vmdk, which is why
# the file is stored as .qcow2, and why the "local" storage carries the import
# content type (ansible/roles/pve_storage). The "26.04" in the file name is
# historical - the image is 24.04 (noble) - and renaming it would replace the
# resource, i.e. re-download it.
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

  # linuxcontainers.org keeps a build for a few weeks only, and this one is
  # gone. With overwrite = true (the provider default) every plan re-reads the
  # URL's metadata and warns that it cannot; false keeps the downloaded file
  # as it is, which the checksum already pins.
  overwrite = false
}


