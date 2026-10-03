# ============================================================================
# GUEST VIRTUAL MACHINES
# ============================================================================
# Guests live behind the firewall. It starts first (startup order 1) and
# guests follow at order 2, so nothing boots into a network without a gateway.

# ---------------------------------------------------------------------------
# Ubuntu Desktop - GPU passthrough workstation (ubuntu-desktop-bootstrap.md)
# ---------------------------------------------------------------------------
# NOT a cloud image guest: q35 + OVMF, no virtual display, both GPUs and the
# laptop's own USB devices handed to the guest. It consumes the vfio-pci
# bindings the gpu_passthrough Ansible role sets up (--tags gpu), so those have
# to exist before it starts.
#
# Its data disk is the host's whole second NVMe (nvme0n1), passed through as
# scsi1 - the host must never use that disk itself.
#
# Starting it hands the screen and the built-in keyboard to the guest. SSH to
# the host still works; that is the way back.
module "ubuntu_desktop_vm" {
  source = "../../modules/ubuntu_desktop"
  count  = var.create_desktop ? 1 : 0

  node_name      = var.node_name
  vm_id          = 102
  vm_name        = "ubuntu-desktop"
  network_bridge = local.networks.lan.bridge
  image_file_id  = proxmox_download_file.ubuntu_desktop_qcow2[0].id
  datastore_id   = var.desktop_datastore

  # The image carries no cloud-init, so the address comes from an OPNsense
  # DHCP reservation against this MAC: local.addresses.ubuntu_desktop.
  mac_address = var.desktop_mac_address

  depends_on = [module.firewall]
}
