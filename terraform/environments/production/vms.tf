# ============================================================================
# GUEST VIRTUAL MACHINES
# ============================================================================
# Guests live behind the firewall. It starts first (startup order 1) and
# guests follow at order 2, so nothing boots into a network without a gateway.

# ---------------------------------------------------------------------------
# Persistent data disks (data_disks)
# ---------------------------------------------------------------------------
# One per entry, on the host's "vmdata" storage, each owned by its own holder
# VM (9000 + the VM's ID) so it outlives the VM that uses it. The storage is
# host state, created by Ansible (roles/pve_storage, proxmox-bootstrap.md).
module "data_disk" {
  source   = "../../modules/data_disk"
  for_each = var.data_disks

  node_name = var.node_name
  for_vm_id = tonumber(each.key)
  vm_id     = 9000 + tonumber(each.key)
  name      = "data-${each.key}"
  size      = each.value
}

# ---------------------------------------------------------------------------
# Ubuntu Desktop - GPU passthrough workstation (ubuntu-desktop-bootstrap.md)
# ---------------------------------------------------------------------------
# NOT a cloud image guest: q35 + OVMF, no virtual display, both GPUs and the
# laptop's own USB devices handed to the guest. It consumes the vfio-pci
# bindings the gpu_passthrough Ansible role sets up (--tags gpu), so those have
# to exist before it starts.
#
# Its OS disk is disposable; what has to survive a rebuild lives on its data
# disk, data_disks["102"], attached as scsi1.
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
  data_disk      = try(module.data_disk["102"].disk, null)

  # The image carries no cloud-init, so the address comes from an OPNsense
  # DHCP reservation against this MAC: local.addresses.ubuntu_desktop.
  mac_address = var.desktop_mac_address

  depends_on = [module.firewall]
}
