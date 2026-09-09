# ============================================================================
# THE FIREWALL - everything internal routes through this
# ============================================================================
# See locals.tf for the topology and docs/network.md for the post-install
# configuration that actually enforces the policy.
#
# The bridges this attaches to (vmbr1/2/3) are host OS state created by
# Ansible: ansible/roles/network_bridge. Run `./sync.sh --run --tags network`
# before the first `terraform apply`, or the VM will fail to start with
# "bridge 'vmbr2' does not exist".

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

  cores  = var.firewall_cores
  memory = var.firewall_memory
}
