# ============================================================================
# THE FIREWALL - everything internal routes through this (opnsense-bootstrap.md)
# ============================================================================
# See locals.tf for the topology. The policy itself is applied over the API by
# ansible/playbooks/opnsense.
#
# The bridges this attaches to (vmbr1/2/3) are host OS state created by Ansible
# (roles/network_bridge). Run playbooks/proxmox/site.yml before the first
# `terraform apply`, or the VM fails to start with "bridge 'vmbr2' does not
# exist" (proxmox-bootstrap.md).

module "firewall" {
  source = "../../modules/opnsense"

  proxmox_node = var.node_name
  vm_id        = 100
  vm_name      = "opnsense-fw"
  iso_file_id  = proxmox_download_file.opnsense_iso.id

  wan_bridge = "vmbr0"
  lan_bridge = local.networks.lan.bridge
  dmz_bridge = local.networks.dmz.bridge
  lab_bridge = local.networks.lab.bridge

  # true: the firewall is installed and WAN is 192.168.1.201. Only a reinstall
  # needs false - see the variable; the factory default is 192.168.1.1, which
  # collides with the home router.
  wan_connected = var.firewall_wan_connected
}
