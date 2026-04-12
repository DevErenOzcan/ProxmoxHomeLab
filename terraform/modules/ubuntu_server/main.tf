terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

variable "node_name" { type = string }
variable "vm_id" { type = number }
variable "vm_name" { type = string }
variable "ip_address" { type = string }
variable "gateway" { type = string, default = "192.168.3.1" }
variable "network_bridge" { type = string, default = "vmbr1" }

resource "proxmox_virtual_environment_vm" "ubuntu_server" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Ubuntu Server VM (8GB RAM)"

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 8192 # 8GB RAM olarak güncellendi
  }

  disk {
    datastore_id = "local-lvm"
    file_id      = "local:iso/ubuntu-22.04.iso"
    interface    = "scsi0"
    size         = 120
  }

  operating_system {
    type = "l26"
  }

  network_device {
    bridge = var.network_bridge
  }

  # Cloud-init ile otomatik statik IP ataması
  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}