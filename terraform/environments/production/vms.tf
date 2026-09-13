# ============================================================================
# GUEST VIRTUAL MACHINES
# ============================================================================
# All of these live on the LAN segment (10.10.10.0/24) behind the firewall,
# not on the old flat 192.168.3.0/24.
#
# The firewall starts first (startup order 1) and these follow at order 2, so
# nothing boots into a network without a gateway.

# ---------------------------------------------------------------------------
# Ubuntu Server - cloud image, fully declarative
# ---------------------------------------------------------------------------
# Boots straight to a login prompt with its address, user and SSH keys already
# applied. Nothing to click through.
module "ubuntu_server_vm" {
  source = "../../modules/ubuntu_cloud"
  count  = var.create_guests ? 1 : 0

  node_name   = var.node_name
  vm_id       = 101
  vm_name     = "ubuntu-server"
  description = "Ubuntu Server on the LAN segment. Cloud image + cloud-init. Managed by Terraform."
  tags        = ["ubuntu", "server", "terraform"]

  cloud_image_file_id = proxmox_download_file.ubuntu_cloud_image[0].id

  ip_address     = "${local.addresses.ubuntu_server}/${local.prefix}"
  gateway        = local.networks.lan.gateway
  network_bridge = local.networks.lan.bridge

  username        = var.guest_username
  password        = var.guest_password
  ssh_public_keys = local.guest_ssh_keys

  depends_on = [module.firewall]
}

# ---------------------------------------------------------------------------
# Ubuntu Desktop - GPU passthrough workstation
# ---------------------------------------------------------------------------
# NOT a cloud image guest. This is what the passthrough work was for: q35 +
# OVMF, no virtual display, both GPUs and the laptop's own USB devices handed
# to the guest. It consumes the vfio-pci bindings the gpu_passthrough Ansible
# role sets up.
#
# The passthrough list is unchanged from what this lab ran. Two prerequisites,
# both checked by state_push_terraform.sh before it plans:
#
#   * storage "nvme2" must exist - the pve_storage Ansible role builds it from
#     the reclaimed nvme0n1.
#   * the GPUs must be bound to vfio-pci, which --tags gpu does.
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
  cloud_image_file_id = proxmox_download_file.ubuntu_desktop_qcow2[0].id
  datastore_id   = var.desktop_datastore

  # No cloud-init on an installer ISO, so the address comes from an OPNsense
  # DHCP reservation against this MAC. locals.addresses.ubuntu_desktop
  # (10.10.10.11) is the one to reserve.
  mac_address = var.desktop_mac_address

  depends_on = [module.firewall]
}


