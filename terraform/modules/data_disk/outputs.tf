output "disk" {
  description = <<-EOT
    The disk, in the shape a VM module's data_disk input takes. Built from
    known values rather than read back from the holder, so that attaching it to
    an existing VM plans as a single added disk instead of an unknown disk list
    (the postcondition in main.tf checks the name). depends_on still makes the
    VM wait for the holder.
  EOT
  value = {
    datastore_id      = var.datastore_id
    path_in_datastore = local.volume
    file_format       = "raw"
    size              = var.size
  }
  depends_on = [proxmox_virtual_environment_vm.holder]
}
