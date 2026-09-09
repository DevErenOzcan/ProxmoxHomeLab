# ============================================================================
# GUEST VIRTUAL MACHINES
# ============================================================================
# All of these now live on the LAN segment (10.10.10.0/24) behind the
# firewall, not on the old flat 192.168.3.0/24.
#
# Gated on var.create_guests, default false: a guest has no gateway until
# OPNsense is installed and its LAN interface is up, so bringing them up in
# the same apply as the firewall only produces guests that cannot reach
# anything.
#
#   1. ./sync.sh --run --tags network      (bridges)
#   2. terraform apply                     (firewall only)
#   3. install + configure OPNsense        (docs/network.md)
#   4. terraform apply -var create_guests=true
#
# KNOWN ISSUE, not yet fixed: these three modules attach the installer ISO as
# the OS disk (disk.file_id) and then set cloud-init ip_config. That
# combination cannot work - installer ISOs are not cloud images, so cloud-init
# never runs and the static addresses below are ignored. The fix is to switch
# to Ubuntu cloud images (.img) plus a cdrom-less cloud-init boot, which is a
# rewrite of the three guest modules rather than a tweak. Until then treat
# these as "creates the VM shell, then install by hand from the console".

module "ubuntu_server_vm" {
  source = "../../modules/ubuntu_server"
  count  = var.create_guests ? 1 : 0

  node_name      = var.node_name
  vm_id          = 101
  vm_name        = "ubuntu-server"
  ip_address     = "${local.addresses.ubuntu_server}/${local.prefix}"
  gateway        = local.networks.lan.gateway
  network_bridge = local.networks.lan.bridge
  iso_file_id    = proxmox_download_file.ubuntu_server_iso[0].id

  depends_on = [module.firewall]
}

module "ubuntu_desktop_vm" {
  source = "../../modules/ubuntu_desktop"
  count  = var.create_guests ? 1 : 0

  node_name      = var.node_name
  vm_id          = 102
  vm_name        = "ubuntu-desktop"
  ip_address     = "${local.addresses.ubuntu_desktop}/${local.prefix}"
  gateway        = local.networks.lan.gateway
  network_bridge = local.networks.lan.bridge
  iso_file_id    = proxmox_download_file.ubuntu_desktop_iso[0].id

  depends_on = [module.firewall]
}

module "windows_11_vm" {
  source = "../../modules/windows_11"
  count  = var.create_guests && var.windows_11_iso_url != "" ? 1 : 0

  node_name          = var.node_name
  vm_id              = 103
  vm_name            = "windows-11-desktop"
  ip_address         = "${local.addresses.windows_11}/${local.prefix}"
  gateway            = local.networks.lan.gateway
  network_bridge     = local.networks.lan.bridge
  iso_file_id        = proxmox_download_file.windows_11_iso[0].id
  virtio_iso_file_id = proxmox_download_file.virtio_iso[0].id

  depends_on = [module.firewall]
}
