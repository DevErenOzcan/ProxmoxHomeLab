terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# GPU-passthrough desktop workstation
# ---------------------------------------------------------------------------
# Not a general-purpose Linux guest. This is the machine the whole passthrough
# effort exists for: q35 + OVMF, no virtual display, both GPUs and the laptop's
# own USB devices handed straight through. It consumes the vfio-pci bindings
# that ansible/roles/gpu_passthrough sets up.
#
# The passthrough configuration is deliberately unchanged from what this lab
# ran before. What did change:
#
#   * datastore_id is a variable defaulting to nvme2 - the pool built from the
#     reclaimed nvme0n1. It used to be hardcoded to a storage that no longer
#     existed, so every apply failed.
#   * USB ports 1-2 and 3-2 are gone. They do not exist on this machine and
#     Proxmox refuses to start a VM that claims a missing port.
#   * The cloud-init initialization block is gone. It never did anything: an
#     installer ISO carries no cloud-init, so the address it declared was
#     silently ignored. The MAC is pinned instead, so OPNsense can hold a DHCP
#     reservation for 10.10.10.11.
#
resource "proxmox_virtual_environment_vm" "ubuntu_desktop" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Ubuntu desktop workstation with GPU passthrough. Managed by Terraform."
  tags        = var.tags

  machine = "q35"
  bios    = "ovmf"

  started = var.started
  on_boot = var.on_boot

  startup {
    order = var.startup_order
  }

  cpu {
    cores   = var.cores
    sockets = 1
    type    = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  # No emulated display: the picture comes out of the passed-through GPU.
  vga {
    type = "none"
  }

  scsi_hardware = "virtio-scsi-single"

  disk {
    datastore_id = var.datastore_id
    import_from  = var.cloud_image_file_id
    interface    = "scsi0"
    size         = var.disk_size
    iothread     = true
    discard      = "on"
  }

  dynamic "disk" {
    for_each = var.data_volume_id != "" ? [var.data_volume_id] : []
    content {
      datastore_id      = startswith(disk.value, "/") ? "" : var.datastore_id
      path_in_datastore = startswith(disk.value, "/") ? disk.value : null
      file_id           = startswith(disk.value, "/") ? null : disk.value
      interface         = "scsi1"
      size              = var.data_disk_size
      file_format       = "raw"
    }
  }

  efi_disk {
    datastore_id      = var.datastore_id
    type              = "4m"
    pre_enrolled_keys = true
  }

  boot_order = ["scsi0"]

  network_device {
    bridge      = var.network_bridge
    model       = "virtio"
    mac_address = var.mac_address
    firewall    = true
  }

  dynamic "hostpci" {
    for_each = var.hostpci_devices
    content {
      device = "hostpci${hostpci.key}"
      id     = hostpci.value.device
      pcie   = hostpci.value.pcie
      xvga   = hostpci.value.xvga
    }
  }

  dynamic "usb" {
    for_each = var.usb_ports
    content {
      host = usb.value
    }
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    precondition {
      condition     = length([for d in var.hostpci_devices : d if d.xvga]) <= 1
      error_message = "Only one passed-through device may be the primary display (xvga = true)."
    }
  }
}
