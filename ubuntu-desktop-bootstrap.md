# Ubuntu desktop bootstrap

The GPU workstation (VM 102, `ubuntu-desktop`, 10.10.10.11) from nothing to a
configured desktop: the VM, SSH access for the controller, the data disk, and
the playbook that applies the rest. The last section rebuilds the VM without
losing `/home`.

What makes this VM unusual: it takes both GPUs and the laptop's keyboard,
touchpad, camera and Bluetooth (eight USB ports). **Once it runs, the laptop's
screen and keyboard belong to the guest.** SSH to the host keeps working; that
is the way back.

Its OS disk is disposable. What has to survive lives on a **200 GB persistent
data disk** on the host's `vmdata` storage, owned by a holder VM (`data-102`,
VM 9102) rather than by VM 102, so destroying VM 102 leaves it in place. The
disk carries `/home`: settings, browser profiles, `~/snap`, and anything
installed into the home directory. Apt packages, snaps and repositories are
reinstalled from `group_vars/ubuntu_desktop.yml` instead.

Before you start:

- the host is converged, including GPU passthrough and the `vmdata` storage
  ([proxmox-bootstrap.md](proxmox-bootstrap.md));
- the firewall is running and configured ([opnsense-bootstrap.md](opnsense-bootstrap.md)).
  Its DHCP reservation for the VM's MAC, `BC:24:11:B8:0E:F8`, is what gives the
  desktop `10.10.10.11`: the image has no cloud-init to set an address.

## 1. Check the image

VM 102's OS disk is imported from a pre-built Ubuntu 24.04 desktop image from
linuxcontainers.org, pinned by URL and SHA256 in
`terraform/environments/production/variables.tf`
(`ubuntu_desktop_qcow2_url`, `ubuntu_desktop_qcow2_sha256`).

linuxcontainers.org keeps a build for a few weeks only, and the pinned one is
gone. If the file `local:import/ubuntu-desktop-26.04-amd64.qcow2` is still on
the host (`pvesm list local --content import`), nothing needs to change.
Otherwise pick a current build under
`https://images.linuxcontainers.org/images/ubuntu/noble/amd64/desktop/`, and set
both variables to its `disk.qcow2` and that file's SHA256.

## 2. Create the VM

From `terraform/environments/production/`:

```bash
terraform plan -var-file=secret.tfvars
terraform apply -var-file=secret.tfvars
```

The plan adds the holder `data-102` with its 200 GB disk (`data_disks` in
`variables.tf`), the desktop image and VM 102. VM 102 is created and started:
q35 + OVMF, no virtual display, the AMD iGPU as primary display and the RTX
3050 Ti, eight USB ports, and the data disk as `scsi1`.

`on_boot` is off on purpose - a host reboot should not seize the screen and
keyboard by itself. After one, start it with `qm start 102` on the host.
**Never start `data-102`:** it only holds the disk, and two VMs running on one
disk corrupt it. It carries Proxmox's protection flag, so it cannot be removed
by accident either.

## 3. Give the controller a way in

The desktop appears on the laptop's own screen and logs in as `ubuntu` by
itself (the image's defaults: GDM autologin, passwordless sudo). The image has
no SSH server, so at the desktop, once, open a terminal and:

```bash
sudo apt install -y openssh-server
install -d -m 700 ~/.ssh && cat >> ~/.ssh/authorized_keys    # paste the controller's public key, then Ctrl-D
ip -br addr                                                  # expect 10.10.10.11
```

From the controller (the route to 10.10.0.0/16 must be in place, see the
README):

```bash
ssh ubuntu@10.10.10.11 true
```

From now on the playbook keeps both the package and the key.

## 4. Apply the configuration

From `ansible/`, with the venv active:

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml --check --diff
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml
```

The run installs the Brave and Docker repositories, the packages (the NVIDIA
595 open driver among them), the snaps (VS Code, Discord, Proton VPN), sets the
time zone and the PRIME profile (`on-demand`), and writes the GNOME settings as
dconf system defaults. Everything it does is listed in
`ansible/inventories/production/group_vars/ubuntu_desktop.yml`.

Then the data disk (`--tags data`):

1. **Formatted only when completely blank** - no partition table, no
   filesystem, nothing `blkid` recognises - as ext4 labelled `desktop-data`. A
   disk with anything else on it stops the run untouched.
2. Mounted at `/mnt/data` by that label.
3. `/home` is bind-mounted from `/mnt/data/home`. The first time, the current
   `/home` is copied there first. **This closes the desktop session for a
   minute or two:** the display manager and the user's own services are
   stopped while the copy runs, then the display manager starts again and logs
   in as before. On a rebuilt VM the disk's copy simply comes back.

The old `/home` stays underneath the bind mount, on the OS disk. Once the new
one is checked, free that space through a non-recursive bind of `/`, which
shows the OS disk without the mounts on top of it:

```bash
sudo mkdir /tmp/rootview && sudo mount --bind / /tmp/rootview
sudo find /tmp/rootview/home -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sudo umount /tmp/rootview && sudo rmdir /tmp/rootview
```

Reboot the desktop once after the first run: the NVIDIA driver and the PRIME
profile take effect at boot.

## 5. What stays manual

- **Remote Desktop.** The playbook enables GNOME's RDP server, but its
  credentials live in the user's keyring and never in this repo: set them in
  Settings → System → Remote Desktop. Then connect to `10.10.10.11:3389`.
- **Anything installed outside the home directory.** Add apt packages, snaps
  and system settings to `group_vars/ubuntu_desktop.yml`, or a rebuilt desktop
  will not have them.

## Rebuilding the VM

When the OS is beyond repair, replace the VM - its data disk stays:

```bash
terraform apply -var-file=secret.tfvars -replace='module.ubuntu_desktop_vm[0].proxmox_virtual_environment_vm.ubuntu_desktop'
```

Proxmox destroys VM 102 and its own disks (the OS and EFI disks), but skips
`vm-9102-disk-0`, which belongs to `data-102`. The new VM gets a fresh OS disk
from the image and the same data disk as `scsi1`. Then repeat
[step 3](#3-give-the-controller-a-way-in) and [step 4](#4-apply-the-configuration):
the playbook finds the `desktop-data` filesystem and binds its `/home` back.

The data disk is persistent, not backed up: it lives on one NVMe, and a failed
disk takes it along. Keep copies of what matters elsewhere.
