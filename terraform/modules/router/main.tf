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
  description = "pfSense/OPNsense firewall router (blank install)"

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  # Blank OS disk - the installer writes here
  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 32
    file_format  = "raw"
  }

  # Attach the ISO Terraform downloaded as a CD-ROM
  cdrom {
    enabled   = true
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  # NIC 1: WAN (home network)
  network_device {
    bridge      = "vmbr0"
    mac_address = var.wan_mac_address
    model       = "virtio"
  }

  # NIC 2: LAN (isolated Proxmox network)
  network_device {
    bridge = "vmbr1"
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }
}