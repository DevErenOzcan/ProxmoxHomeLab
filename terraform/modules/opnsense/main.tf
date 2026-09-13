terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# OPNsense firewall / router
# ---------------------------------------------------------------------------
# Replaces the old modules/router. Differences that matter:
#   - four interfaces instead of two, so LAN / DMZ / LAB are separate L3
#     segments the firewall can rule between, not one flat network
#   - starts first (startup.order = 1) with a delay, so no guest boots into a
#     network without a gateway
#   - cpu type 'host' so AES-NI reaches FreeBSD
#
# The install itself is interactive - OPNsense has no unattended installer.
# See docs/network.md for the post-install interface assignment and the exact
# firewall rules that implement "guests cannot reach the home LAN, but I can
# reach the guests".
#
resource "proxmox_virtual_environment_vm" "opnsense" {
  name        = var.vm_name
  node_name   = var.proxmox_node
  vm_id       = var.vm_id
  description = "OPNsense firewall. WAN on ${var.wan_bridge}; LAN/DMZ/LAB on ${var.lan_bridge}/${var.dmz_bridge}/${var.lab_bridge}. Managed by Terraform."
  tags        = var.tags

  started = var.started
  on_boot = true

  # Nothing else should come up before the gateway exists.
  startup {
    order    = var.startup_order
    up_delay = var.startup_up_delay
  }

  cpu {
    cores = var.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    import_from  = var.iso_file_id
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = "raw"
    iothread     = true
    discard      = "on"
  }

  boot_order = ["scsi0"]

  # -- net0 -> vtnet0 -- WAN, faces the home network ------------------------
  # Starts DISCONNECTED, and that is not paranoia. A fresh OPNsense boots its
  # factory config, which is LAN = 192.168.1.1/24 with a DHCP server on it. On
  # a home network that already uses 192.168.1.0/24 the VM then answers ARP for
  # the real router's address and hands out its own leases -- it takes the
  # house offline, not just the lab. Connect this only after the console has
  # assigned interfaces and given WAN its static address.
  network_device {
    bridge       = var.wan_bridge
    model        = "virtio"
    mac_address  = var.wan_mac_address
    firewall     = false
    disconnected = !var.wan_connected
  }

  # -- net1 -> vtnet1 -- LAN, trusted guests --------------------------------
  network_device {
    bridge   = var.lan_bridge
    model    = "virtio"
    firewall = false
  }

  # -- net2 -> vtnet2 -- DMZ, internet-facing services + cloudflared --------
  network_device {
    bridge   = var.dmz_bridge
    model    = "virtio"
    firewall = false
  }

  # -- net3 -> vtnet3 -- LAB, experiments and quarantine --------------------
  network_device {
    bridge   = var.lab_bridge
    model    = "virtio"
    firewall = false
  }

  operating_system {
    type = "other" # FreeBSD
  }

  # OPNsense ships qemu-guest-agent but it is off until you enable it in
  # System > Settings > Administration. Claiming it here would make Terraform
  # wait for an agent that never answers.
  agent {
    enabled = false
  }

  lifecycle {
    ignore_changes = [
      # The installer partitions the disk; do not let a provider upgrade
      # decide the disk drifted and offer to recreate the firewall.
      disk,
    ]
  }
}
