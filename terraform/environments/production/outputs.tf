# ============================================================================
# What you need in front of you after `terraform apply`
# ============================================================================

output "opnsense_interface_map" {
  description = "Interface assignment the OPNsense installer asks for. vtnetN order follows the NIC order in modules/opnsense/main.tf."
  value       = module.firewall.interface_map
}

output "opnsense_addresses" {
  description = "Addresses to give each OPNsense interface during setup"
  value = {
    WAN = "${local.addresses.opnsense_wan}/${local.prefix} via ${local.home_lan.gateway}"
    LAN = "${local.addresses.opnsense_lan}/${local.prefix}"
    DMZ = "${local.addresses.opnsense_dmz}/${local.prefix}"
    LAB = "${local.addresses.opnsense_lab}/${local.prefix}"
  }
}

output "home_router_static_route" {
  description = "The single route to add on the home router so you can reach every segment from the home network"
  value       = "${local.internal_supernet} -> ${local.addresses.opnsense_wan}"
}

output "fallback_route_commands" {
  description = "If the home router cannot do static routes, add the route on your own machine instead"
  value = {
    windows = "route -p add 10.10.0.0 mask 255.255.0.0 ${local.addresses.opnsense_wan}"
    linux   = "sudo ip route add ${local.internal_supernet} via ${local.addresses.opnsense_wan}"
    macos   = "sudo route -n add -net ${local.internal_supernet} ${local.addresses.opnsense_wan}"
  }
}

output "segments" {
  description = "The internal segments and what belongs in each"
  value = {
    for k, v in local.networks : upper(k) => {
      bridge  = v.bridge
      cidr    = v.cidr
      gateway = v.gateway
      purpose = v.description
    }
  }
}

output "reserved_addresses" {
  description = "Static addresses this repo assumes"
  value       = local.addresses
}

output "next_steps" {
  description = "Order of operations for a rebuild from scratch; the bootstrap guides at the repo root have the full command lines"
  value = [
    "1. proxmox-bootstrap.md         playbooks/proxmox/site.yml (bridges, vfio-pci, storage content types)",
    "2. opnsense-bootstrap.md        terraform apply with the WAN unplugged, console install, then playbooks/opnsense/site.yml",
    "3. Add the static route from output home_router_static_route on the controller",
    "4. ubuntu-desktop-bootstrap.md  terraform apply (the desktop), then playbooks/ubuntu_desktop/site.yml",
  ]
}
