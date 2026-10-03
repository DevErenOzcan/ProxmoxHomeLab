# Ubuntu desktop bootstrap

The GPU workstation (VM 102, `ubuntu-desktop`, 10.10.10.11) from nothing to a
configured desktop: the VM, SSH access for the controller, the data disk, and
the playbook that applies the rest.

What makes this VM unusual: it takes both GPUs, the laptop's keyboard,
touchpad, camera and Bluetooth (eight USB ports), and the whole second NVMe.
**Once it runs, the laptop's screen and keyboard belong to the guest.** SSH to
the host keeps working; that is the way back.

Before you start:

- the host is converged, including GPU passthrough
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

The plan should only add the desktop image and VM 102. The VM is created and
started: q35 + OVMF, no virtual display, the AMD iGPU as primary display and
the RTX 3050 Ti, eight USB ports, and `/dev/nvme0n1` as its second disk.

`on_boot` is off on purpose - a host reboot should not seize the screen and
keyboard by itself. After one, start it with `qm start 102` on the host.

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

## 4. The data disk

The host's `nvme0n1` is the guest's `/dev/sdb`. The playbook mounts its
filesystem by UUID and **never formats anything**.

- **The disk already has the data filesystem** (a rebuilt VM): nothing to do.
  `desktop_data_volume_uuid` in `group_vars/ubuntu_desktop.yml` already names
  it.
- **The disk is new or empty**: create a GPT and one ext4 partition (gparted
  arrives with the playbook's `base` tag), then put the new filesystem's UUID
  into `desktop_data_volume_uuid`:

  ```bash
  sudo blkid /dev/sdb1
  ```

## 5. Apply the configuration

From `ansible/`, with the venv active:

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml --check --diff
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml
```

The run installs the Brave and Docker repositories, the packages (the NVIDIA
595 open driver among them), the snaps (VS Code, Discord, Proton VPN), sets the
time zone and the PRIME profile (`on-demand`), writes the GNOME settings as
dconf system defaults, and mounts the data volume at `/mnt/data` with
`~/Projects` linked to it. Everything it does is listed in
`ansible/inventories/production/group_vars/ubuntu_desktop.yml`.

Reboot the desktop once afterwards: the NVIDIA driver and the PRIME profile
take effect at boot.

## 6. What stays manual

- **Remote Desktop.** The playbook enables GNOME's RDP server, but its
  credentials live in the user's keyring and never in this repo: set them in
  Settings → System → Remote Desktop. Then connect to `10.10.10.11:3389`.
- **Anything installed by hand later.** Add it to `group_vars/ubuntu_desktop.yml`,
  or a rebuilt desktop will not have it.
