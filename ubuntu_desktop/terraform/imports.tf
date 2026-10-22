# Adopts the running VMs into an empty state instead of creating new ones:
# the first plan reads them from the Proxmox API, and the apply records them.
# Once they are in the state these blocks do nothing.
#
# Building from nothing, with no VM 102 or 9102 on the host, delete this file
# first: an import of a VM that does not exist fails the plan.
import {
  to = proxmox_virtual_environment_vm.data_disk
  id = "proxmox/9102"
}

import {
  to = proxmox_virtual_environment_vm.desktop
  id = "proxmox/102"
}
