terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

variable "node_name" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "vm_name" {
  type = string
}

resource "proxmox_virtual_environment_vm" "ubuntu" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Ubuntu Server VM"

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/ubuntu-22.04.iso"
    interface    = "scsi0"
    size         = 32
  }

  operating_system {
    type = "l26"
  }

  network_device {
    bridge = "vmbr0"
  }

  initialization {
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }
}
