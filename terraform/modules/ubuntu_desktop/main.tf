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
# Every value below mirrors VM 102 as it runs (checked against
# /etc/pve/qemu-server/102.conf, 2026-10-03). Three of them look like
# omissions and are not - the provider reads an ABSENT key back as these
# values, so setting anything else is a permanent plan diff:
#
#   * no memory.floating: 102.conf has no balloon key, which reads back as 0
#   * no rombar on hostpci: an absent rombar reads back as true
#   * no usb3 on usb: an absent usb3 reads back as false
#
# The image carries no cloud-init drive, so the MAC is pinned instead and
# OPNsense holds a DHCP reservation for 10.10.10.11 against it.
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

  # The data disk. An absolute path is a whole host block device passed
  # through (live: /dev/nvme0n1); anything else is a volume ID on a datastore.
  # For a passthrough disk the provider reports no file_format, so setting one
  # is a permanent diff - it is left null there.
  dynamic "disk" {
    for_each = var.data_volume_id != "" ? [var.data_volume_id] : []
    content {
      datastore_id      = startswith(disk.value, "/") ? "" : var.datastore_id
      path_in_datastore = startswith(disk.value, "/") ? disk.value : null
      file_id           = startswith(disk.value, "/") ? null : disk.value
      interface         = "scsi1"
      size              = var.data_disk_size
      file_format       = startswith(disk.value, "/") ? null : "raw"
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
      pcie   = hostpci.value.pcie ? true : null
      xvga   = hostpci.value.xvga ? true : null
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
