terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "virtual_router" {
  name        = var.router_name
  node_name   = var.proxmox_node
  vm_id       = var.vm_id
  description = "pfSense/OPNsense Firewall Router"

  clone {
    vm_id = var.router_template_id
    full  = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # 1. AĞ BACAĞI: WAN (Ev Ağı)
  network_device {
    bridge      = "vmbr0"
    mac_address = var.wan_mac_address
    model       = "virtio"
  }

  # 2. AĞ BACAĞI: LAN (İzole Proxmox Ağı)
  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}