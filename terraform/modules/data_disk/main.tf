terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

# ---------------------------------------------------------------------------
# A persistent data disk, owned by a VM that only holds it
# ---------------------------------------------------------------------------
# Proxmox deletes a VM's own disks with the VM. A disk owned by ANOTHER VMID
# is skipped (qemu-server's destroy_vm frees a volume only when its owner is
# the VM being destroyed), so the disk lives here, on a holder that is never
# started, and the VM that uses it attaches it (the `disk` output). That VM can
# then be destroyed and rebuilt without the data going with it. This is the
# provider's "attached disks" pattern; its documentation marks it experimental.
#
# Each VM that attaches a holder's disk sees only that disk; on thick-LVM
# storage with saferemove, a deleted disk is zeroed before its space can be
# handed to another VM.
#
# Never start the holder, and never move or resize its disk through it.
resource "proxmox_virtual_environment_vm" "holder" {
  name        = var.name
  node_name   = var.node_name
  vm_id       = var.vm_id
  description = "Holds a persistent data disk for VM ${var.for_vm_id}. Never started. Managed by Terraform."
  tags        = var.tags

  started = false
  on_boot = false

  # Proxmox refuses to remove a protected VM or its disks, from the GUI too.
  protection = true

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.size
    file_format  = "raw"
  }

  lifecycle {
    # Destroying the holder destroys the data. Remove this module instance
    # deliberately, after turning protection off, if that is what you want.
    prevent_destroy = true

    # The `disk` output names the volume before it exists, so that a VM
    # attaching it plans with known values. Proxmox gives a new VM's first disk
    # exactly this name; if it ever did not, stop here.
    postcondition {
      condition     = self.disk[0].path_in_datastore == local.volume
      error_message = "The holder's disk is ${self.disk[0].path_in_datastore}, not ${local.volume}; the `disk` output would point at the wrong volume."
    }
  }
}

locals {
  volume = "vm-${var.vm_id}-disk-0"
}
