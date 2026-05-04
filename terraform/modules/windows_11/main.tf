terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "windows_11" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id
  machine   = "q35"
  bios      = "ovmf"

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

  # Windows 11 için ZORUNLU TPM 2.0
  tpm_state {
    datastore_id = "nvme2"
    version      = "v2.0"
  }

  # 1. CD-ROM: Windows 11 Kurulum ISO'su
  cdrom {
    enabled   = true
    file_id   = var.iso_file_id
    interface = "ide2"
  }

  # 2. CD-ROM: VirtIO Sürücüleri (Windows'un Diski ve Ağı görmesi için şart)
  cdrom {
    enabled   = true
    file_id   = var.virtio_iso_file_id
    interface = "ide0"
  }

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    mac_address = "BC:24:11:B8:0E:F9" # Çakışmayı önlemek için Ubuntu'dan farklı yapıldı
    firewall    = true
  }

  # USB Passthrough (Ubuntu Desktop ile aynı)
  usb { host = "1-3" }
  usb { host = "1-4" }
  usb { host = "3-2" }
  usb { host = "3-3" }
  usb { host = "3-4" }
  usb { host = "1-2" }

  # GPU / PCIe Passthrough (Ubuntu Desktop ile aynı)
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

  initialization {
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
  }
}