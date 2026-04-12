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

resource "proxmox_virtual_environment_vm" "ubuntu_desktop" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id

  machine = "q35"
  bios    = "ovmf"

  cpu {
    cores   = 12
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 16384
  }

  vga {
    type = "none"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = "nvme2"
    interface    = "scsi0"
    size         = 300
    iothread     = true
    file_format  = "raw"
  }

  efi_disk {
    datastore_id      = "nvme2"
    type              = "4m"
    pre_enrolled_keys = true
  }

  cdrom {
    enabled   = true
    file_id   = "local:iso/ubuntu-24.04.4-desktop-amd64.iso"
    interface = "ide2"
  }

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    mac_address = "BC:24:11:B8:0E:F8"
    firewall    = true
  }

  usb { host = "1-3" }
  usb { host = "1-4" }
  usb { host = "3-2" }
  usb { host = "3-3" }
  usb { host = "3-4" }
  usb { host = "1-2" }
  
  hostpci {
    device = "0000:06:00.0"
    pcie   = true
    xvga   = true
  }
  hostpci {
    device = "0000:01:00"
    pcie   = true
  }
  hostpci {
    device = "0000:06:00.1"
    pcie   = true
  }
  hostpci {
    device = "0000:06:00.2"
    pcie   = true
  }
  hostpci {
    device = "0000:06:00.5"
    pcie   = true
  }
  hostpci {
    device = "0000:06:00.6"
    pcie   = true
  }
  hostpci {
    device = "0000:03:00.0"
    pcie   = true
  }

  # Terraform üzerinden statik IP vermek için
  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}