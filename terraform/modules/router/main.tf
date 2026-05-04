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
  description = "pfSense/OPNsense Firewall Router (Boş Kurulum)"

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Boş bir işletim sistemi diski (Kurulum buraya yapılacak)
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    file_format  = "raw"
  }

  # Terraform'un indirdiği ISO'yu CD-ROM olarak takıyoruz
  cdrom {
    enabled   = true
    file_id   = var.iso_file_id
    interface = "ide2"
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