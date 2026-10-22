# ============================================================================
# ubuntu-desktop - VM 102, and VM 9102 that holds its data disk
# ============================================================================
# The GPU workstation and the controller every playbook and Terraform run in
# these repos starts from. It sits on the home network (vmbr0) at
# 192.168.1.202, an address it sets itself (../roles/desktop_network): the
# image has no cloud-init.
#
# Never apply a change from the desktop that stops or replaces VM 102: the
# run would end with the machine it runs on (README.md, "Rebuilding the VM").

# ---------------------------------------------------------------------------
# The data disk - VM 9102, which is never started
# ---------------------------------------------------------------------------
# Proxmox deletes a VM's own disks together with the VM, but skips a disk that
# belongs to another VM ID. So the desktop's persistent disk belongs to this
# holder, VM 9102, and VM 102 only attaches it (scsi1 below): VM 102 can be
# destroyed and rebuilt, and /home - with this repo and its state - stays.
#
# Never start this VM, and never move or resize its disk through it. Two VMs
# running on one disk corrupt it.
resource "proxmox_virtual_environment_vm" "data_disk" {
  name        = "data-102"
  node_name   = "proxmox"
  vm_id       = 9102
  description = "Holds a persistent data disk for VM 102. Never started. Managed by Terraform."
  tags        = ["data-disk", "terraform"]

  started = false
  on_boot = false

  # Proxmox refuses to remove a protected VM or its disks, from the GUI too.
  protection = true

  # On "vmdata", the host's second NVMe as thick LVM (../host): 200 GB reserved
  # in full. The size must not change afterwards.
  disk {
    datastore_id = "vmdata"
    interface    = "scsi0"
    size         = 200
    file_format  = "raw"
  }

  lifecycle {
    # Destroying the holder destroys /home. Turn protection off and remove
    # this line first, deliberately, if that is ever what you want.
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# The desktop - VM 102
# ---------------------------------------------------------------------------
# q35 + OVMF, no virtual display: the picture comes out of the passed-through
# AMD iGPU, and the laptop's own keyboard, touchpad, camera and Bluetooth are
# handed over too. Once it runs, the laptop's screen and keyboard belong to it.
# The host has to be set up for this first (../host, the "gpu" tag).
#
# Every value mirrors VM 102 as it runs (/etc/pve/qemu-server/102.conf,
# 2026-10-22). The
# provider reads an ABSENT key back as a fixed value, so the code says exactly
# that value, or every plan shows a difference:
#   * no memory.floating: no balloon key, which reads back as 0
#   * rombar = true on hostpci: an absent rombar reads back as true
#   * no usb3 on usb: an absent usb3 reads back as false
resource "proxmox_virtual_environment_vm" "desktop" {
  name        = "ubuntu-desktop"
  node_name   = "proxmox"
  vm_id       = 102
  description = "Ubuntu desktop workstation with GPU passthrough. Managed by Terraform."
  tags        = ["ubuntu", "desktop", "passthrough", "terraform"]

  machine = "q35"
  bios    = "ovmf"

  started = true
  # Off on purpose: a host reboot should not seize the screen and keyboard by
  # itself. After one, start it on the host with `qm start 102`.
  on_boot = false

  startup {
    order = 2
  }

  cpu {
    cores   = 8
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 8 * 1024
  }

  vga {
    type = "none"
  }

  scsi_hardware = "virtio-scsi-single"

  # The OS disk: disposable, imported from the image when the VM is created.
  disk {
    datastore_id = "local-lvm"
    import_from  = var.os_image
    interface    = "scsi0"
    size         = 40
    iothread     = true
    discard      = "on"
  }

  # The persistent disk, VM 9102's. Its name is Proxmox's for a VM's first
  # disk, which is what the holder has.
  disk {
    datastore_id      = "vmdata"
    path_in_datastore = "vm-9102-disk-0"
    file_format       = "raw"
    size              = 200
    interface         = "scsi1"
    iothread          = true
    discard           = "on"
  }

  efi_disk {
    datastore_id      = "local-lvm"
    type              = "4m"
    pre_enrolled_keys = true
  }

  boot_order = ["scsi0"]

  # On the home network. The MAC is pinned: the guest's network profile
  # matches it to set 192.168.1.202.
  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = "BC:24:11:B8:0E:F8"
    # The Proxmox firewall is off at datacenter level, so true would only add
    # the fwbr/fwpr/fwln detour on the host without filtering anything.
    firewall = false
  }

  # hostpci0: the AMD Cezanne iGPU, the primary display - it drives the panel.
  hostpci {
    device = "hostpci0"
    id     = "0000:06:00.0"
    xvga   = true
    rombar = true
  }

  # hostpci1: the NVIDIA RTX 3050 Ti, which renders on request (PRIME).
  hostpci {
    device = "hostpci1"
    id     = "0000:01:00.0"
    rombar = true
  }

  # hostpci2-5: the iGPU's other functions - its HD audio, the platform
  # security processor, the audio coprocessor and the HD audio controller -
  # so the laptop's own sound reaches the guest. 06:00.3 and 06:00.4 are the
  # USB controllers, which stay with the host (single ports go through below).
  dynamic "hostpci" {
    for_each = {
      hostpci2 = "0000:06:00.1"
      hostpci3 = "0000:06:00.2"
      hostpci4 = "0000:06:00.5"
      hostpci5 = "0000:06:00.6"
    }
    content {
      device = hostpci.key
      id     = hostpci.value
      rombar = true
    }
  }

  # USB host PORTS, not devices: whatever is plugged in there belongs to the
  # guest. As of 2026-10-03:
  #   1-2    (empty)                  1-3    integrated camera
  #   1-4    MediaTek Bluetooth       3-3    ITE controller (8176)
  #   3-4    ITE controller (8295)    3-2    (empty)
  #   1-1.1  external hub, port 1     1-1.2  external hub, port 2 (mouse)
  # The ITE devices are the built-in keyboard and touchpad.
  dynamic "usb" {
    for_each = ["1-2", "1-3", "1-4", "3-3", "3-4", "3-2", "1-1.1", "1-1.2"]
    content {
      host = usb.value
    }
  }

  operating_system {
    type = "l26"
  }

  depends_on = [proxmox_virtual_environment_vm.data_disk]

  lifecycle {
    ignore_changes = [
      # The provider reads only usb0-usb3; this VM has eight ports. They are
      # set at creation and changed with `qm set` afterwards.
      usb,
      # The image only matters at creation, and the API does not report it.
      disk[0].import_from,
    ]
  }
}
