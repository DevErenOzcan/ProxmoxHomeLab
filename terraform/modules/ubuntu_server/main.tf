terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# A headless Ubuntu Server guest from Ubuntu's cloud image
# ---------------------------------------------------------------------------
# The OS disk is imported from the cloud image and grown to disk_size on first
# boot. cloud-init, from the drive Proxmox writes, sets the static address,
# the DNS server and the SSH keys of the default "ubuntu" user, which has no
# password. That is all a guest needs before Ansible takes over over SSH.
#
# No guest agent: the image does not ship qemu-guest-agent, and with the agent
# enabled the provider waits for it on every create. The address is static, so
# nothing has to be read back from the guest.
#
# The display is the serial console: cloud images log to ttyS0, and the
# Proxmox console shows it (xterm.js).
resource "proxmox_virtual_environment_vm" "server" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = var.description
  tags        = var.tags

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

  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
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

  # The persistent data disk, owned by a modules/data_disk holder rather than
  # by this VM: destroying and rebuilding this VM leaves it, and its data, in
  # place. The guest mounts it by label (ansible/roles/data_volume).
  dynamic "disk" {
    for_each = var.data_disk == null ? [] : [var.data_disk]
    content {
      datastore_id      = disk.value.datastore_id
      path_in_datastore = disk.value.path_in_datastore
      file_format       = disk.value.file_format
      size              = disk.value.size
      interface         = "scsi1"
      iothread          = true
      discard           = "on"
    }
  }

  boot_order = ["scsi0"]

  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      username = var.username
      keys     = var.ssh_public_keys
    }
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
    # The Proxmox firewall is off at datacenter level, so true would only add
    # the fwbr/fwpr/fwln detour on the host without filtering anything.
    firewall = false
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    # The image only matters at creation. Without this, a newer image build
    # would plan to replace every running guest made from the old one.
    ignore_changes = [disk[0].import_from]
  }
}
