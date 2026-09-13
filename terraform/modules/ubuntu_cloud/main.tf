terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# An Ubuntu guest built from a cloud image
# ---------------------------------------------------------------------------
# Replaces modules/ubuntu_server, which attached an installer ISO as the OS
# disk and then set cloud-init ip_config on top. That cannot work: an installer
# ISO is not a bootable disk image and carries no cloud-init, so the VM booted
# to nothing and the static address was silently ignored.
#
# The working shape is: import a cloud image as the disk, and let Proxmox's
# native cloud-init drive set the user, keys and address. No snippets storage
# is needed for that -- only user_data_file_id would require one.
#
resource "proxmox_virtual_environment_vm" "this" {
  name        = var.vm_name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = var.description
  tags        = var.tags

  started = var.started
  on_boot = true

  startup {
    order    = var.startup_order
    up_delay = var.startup_up_delay
  }

  cpu {
    cores = var.cores
    type  = var.cpu_type
  }

  memory {
    dedicated = var.memory
  }

  agent {
    enabled = var.agent_enabled
    timeout = "1m"
  }

  # import_from copies the image into the datastore once, at create time.
  # Changing it later is ignored by the provider, so a new image means a new VM.
  disk {
    datastore_id = var.datastore_id
    import_from  = var.cloud_image_file_id
    interface    = "virtio0"
    size         = var.disk_size
    iothread     = true
    discard      = "on"
  }

  initialization {
    datastore_id = var.datastore_id
    interface    = "ide2"
    upgrade      = var.cloud_init_upgrade

    dns {
      servers = length(var.dns_servers) > 0 ? var.dns_servers : [var.gateway]
    }

    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.ip_address == "dhcp" ? null : var.gateway
      }
    }

    user_account {
      username = var.username
      password = var.password != "" ? var.password : null
      keys     = var.ssh_public_keys
    }
  }

  network_device {
    bridge   = var.network_bridge
    model    = "virtio"
    firewall = false
  }

  operating_system {
    type = "l26"
  }

  lifecycle {
    precondition {
      condition     = length(var.ssh_public_keys) > 0 || var.password != ""
      error_message = "${var.vm_name} would have no way to log in. Give it ssh_public_keys, or set guest_password."
    }
  }
}
