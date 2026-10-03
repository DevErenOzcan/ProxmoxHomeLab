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
# /etc/pve/qemu-server/102.conf, 2026-10-03). The provider reads an ABSENT key
# back as a fixed value, so the code must say exactly that value or every plan
# shows a diff:
#
#   * no memory.floating: 102.conf has no balloon key, which reads back as 0
#   * rombar = true on hostpci: an absent rombar reads back as true, and a null
#     here is a diff against it (seen in the first real plan, 2026-10-03)
#   * no usb3 on usb: an absent usb3 reads back as false
#
# USB is ignored after creation: bpg/proxmox 0.113.1 reads only usb0-usb3
# (maxResourceVirtualEnvironmentVMHostUSBDevices = 4), while this VM has eight
# ports. The list still creates all eight; changing them later is a GUI or
# `qm set` job.
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
    import_from  = var.image_file_id
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
    # The Proxmox firewall is off at datacenter level, so true would only add
    # the fwbr/fwpr/fwln detour on the host without filtering anything.
    firewall = false
  }

  dynamic "hostpci" {
    for_each = var.hostpci_devices
    content {
      device = "hostpci${hostpci.key}"
      id     = hostpci.value.device
      pcie   = hostpci.value.pcie ? true : null
      xvga   = hostpci.value.xvga ? true : null
      rombar = true
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
    # See the header: the provider cannot see usb4 and up.
    ignore_changes = [usb]

    precondition {
      condition     = length([for d in var.hostpci_devices : d if d.xvga]) <= 1
      error_message = "Only one passed-through device may be the primary display (xvga = true)."
    }
  }
}
