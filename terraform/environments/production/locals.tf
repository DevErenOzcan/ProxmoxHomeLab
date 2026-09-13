# ============================================================================
# THE NETWORK PLAN - single source of truth
# ============================================================================
#
# Physical reality: the host has exactly ONE NIC (nic0, in vmbr0). The MT7921
# wireless card is reserved for GPU/PCI passthrough, so it cannot carry host
# traffic. The firewall is therefore "router-on-a-stick": its WAN leg sits on
# the home LAN and every internal segment lives on a port-less Linux bridge.
#
#   internet ── home router (192.168.1.1)
#                    │
#                    │  192.168.1.0/24   <- home network, NOT behind the firewall
#                    ├──────────────── Proxmox host  192.168.1.200  (vmbr0)
#                    │                  stays here on purpose: if the firewall
#                    │                  VM dies, the PVE web UI is still up
#                    │
#                    └──────────────── OPNsense WAN  192.168.1.201  (vmbr0)
#                                            │
#                        ┌───────────────────┼───────────────────┐
#                     vmbr1               vmbr2               vmbr3
#                   LAN 10.10.10.1      DMZ 10.10.20.1      LAB 10.10.30.1
#                   trusted guests      Cloudflare-facing   experiments,
#                                       services +          untrusted things
#                                       cloudflared
#
# Why 10.10.x.x and not 192.168.x.x: all three segments fall inside a single
# 10.10.0.0/16 supernet, so reaching them from the home network needs exactly
# ONE static route on the home router instead of three:
#
#     10.10.0.0/16  ->  192.168.1.201
#
# The bridges themselves are created by Ansible (roles/network_bridge), not
# here - they are host OS state. Terraform only attaches guests to them.
# Keep this file and ansible/inventory/group_vars/proxmox_nodes.yml in step.
#
locals {
  # ---- the home network the host already lives on -------------------------
  home_lan = {
    cidr    = "192.168.1.0/24"
    gateway = "192.168.1.1"
  }

  # ---- every internal segment, summarised by one route --------------------
  internal_supernet = "10.10.0.0/16"

  networks = {
    lan = {
      bridge      = "vmbr1"
      cidr        = "10.10.10.0/24"
      gateway     = "10.10.10.1"
      description = "Trusted guests - the VMs you work on"
    }
    dmz = {
      bridge      = "vmbr2"
      cidr        = "10.10.20.0/24"
      gateway     = "10.10.20.1"
      description = "Internet-facing services and cloudflared - may not initiate into LAN"
    }
    lab = {
      bridge      = "vmbr3"
      cidr        = "10.10.30.0/24"
      gateway     = "10.10.30.1"
      description = "Experiments and quarantine - isolated from LAN and DMZ"
    }
  }

  # ---- fixed addresses ----------------------------------------------------
  # Guests get static addresses so firewall rules can name them. DHCP pools
  # start at .100 (configured on OPNsense) and are for throwaway guests.
  addresses = {
    opnsense_wan = "192.168.1.76"
    opnsense_lan = local.networks.lan.gateway
    opnsense_dmz = local.networks.dmz.gateway
    opnsense_lab = local.networks.lab.gateway

    cloudflared    = "10.10.20.10" # reserved: the Cloudflare Tunnel container
    ubuntu_server  = "10.10.10.10"
    ubuntu_desktop = "10.10.10.11"
  }

  prefix = 24

  # ---- guest login ---------------------------------------------------------
  # Terraform runs on the Proxmox host, so these paths are the host's. Missing
  # files drop out rather than failing the plan.
  guest_ssh_keys = compact([
    for f in var.guest_ssh_public_key_files : try(trimspace(file(f)), "")
  ])
}
