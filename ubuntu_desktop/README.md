# ubuntu_desktop - the GPU workstation and the controller

VM 102 `ubuntu-desktop`: Ubuntu 24.04 with both of the laptop's GPUs and its
keyboard, touchpad, camera and Bluetooth passed through - and the
**controller**, the machine every playbook and Terraform run starts from,
this repo's and `librenfra`'s. It sits on the home network at
`192.168.1.202`, outside the firewall.

| Path | What it is |
|---|---|
| `site.yml` | the playbook for the desktop's own state; it runs on the desktop itself |
| `host_vars/desktop.yml` | every setting: network, packages, snaps, GNOME, the data disk |
| `inventory.yml` | the desktop, `ansible_connection: local` |
| `roles/` | `desktop_base`, `desktop_network`, `desktop_gnome`, `data_volume` |
| `terraform/` | VM 102 and VM 9102, which holds its data disk |
| `ansible.cfg`, `requirements.yml` | Ansible settings and the collections the roles need |

**Once VM 102 runs, the laptop's screen and keyboard belong to it.** SSH to
the host keeps working; that is the way back.

## How it is put together

- **The network.** VM 102's NIC is on `vmbr0`, the home network. The address
  is static, set inside the guest by a NetworkManager profile
  (`desktop_network`): `192.168.1.202/24`, gateway and DNS `192.168.1.1`, and
  the route `10.10.0.0/16 via 192.168.1.201` into the segments behind the
  firewall. The home router can hold no reservation; `.202` is outside its
  DHCP pool.
- **The data disk.** The OS disk is disposable. What has to survive is on a
  200 GB disk on the host's `vmdata` storage, owned by VM 9102 (`data-102`) -
  which is never started - and attached to VM 102 as `scsi1`. Proxmox frees
  only a VM's own disks when it is destroyed, so VM 102 can be rebuilt and the
  disk stays. It carries `/home`: settings, browser profiles, `~/snap` - and
  the controller's checkout of this repo, with the Terraform state and the
  secrets. Packages, snaps and repositories are not on it: `site.yml`
  reinstalls them.
- **The controller's tools.** `site.yml` installs Terraform (from HashiCorp's
  repository) and `python3-venv`; Ansible itself lives in the repo's `.venv`.
  The controller's SSH key is `~/.ssh/id_ed25519` (`controller-ubuntu-desktop`),
  in root's `authorized_keys` on the host.

**Back up what exists only here.** The data disk is persistent, not backed
up. Keep a copy of `terraform/terraform.tfstate`, `terraform/secret.tfvars`
and `~/.ssh/id_ed25519` off the laptop.

## Running it

On the desktop, from this directory, with the venv active:

```bash
ansible-playbook site.yml --check --diff
```

```bash
ansible-playbook site.yml
```

`--tags base|network|gnome|data` runs one part. A dry run reports Docker's
signing key as changed whenever download.docker.com answers 200: check mode
cannot compare the key's contents, and a real run finds them the same.

Terraform, from `terraform/`:

```bash
terraform plan -var-file=secret.tfvars
```

`secret.tfvars` holds the host's root password; start from
`secret.tfvars.example`.

## Building it from nothing

The controller cannot create itself, so this is the one machine that starts
somewhere else.

### 1. The disk image

VM 102's OS disk is imported from a pre-built Ubuntu 24.04 desktop image from
linuxcontainers.org, which has to be on the host as
`local:import/ubuntu-desktop-26.04-amd64.qcow2` (`os_image` in
`terraform/variables.tf`; the "26.04" in the name is historical). Check with
`pvesm list local --content import` on the host. If it is not there, take a
current build's `disk.qcow2` from
`https://images.linuxcontainers.org/images/ubuntu/noble/amd64/desktop/` and
download it to the host under that name: Datacenter → proxmox → local →
Import → Download from URL.

### 2. Create the VM

From any Linux machine on the home network with this repo and Terraform,
in `terraform/`, with `secret.tfvars` in place. Delete `imports.tf` first if
VM 102 and VM 9102 do not exist yet; keep it to adopt them if they do:

```bash
terraform init
```

```bash
terraform apply -var-file=secret.tfvars
```

VM 102 is created and started on `vmbr0`. Until its own profile is written
it takes an address from the home router's DHCP.

### 3. Bring /home back

The desktop appears on the laptop's screen and logs in as `ubuntu` by itself
(the image's defaults: GDM autologin, passwordless sudo). The repo belongs in
`/home`, on the data disk - which a fresh VM has not mounted yet. So the
first checkout is a temporary one, which only binds the data disk. In a
terminal on the desktop:

```bash
sudo apt install -y git python3-venv
git clone https://github.com/DevErenOzcan/ProxmoxHomeLab.git /tmp/bootstrap
cd /tmp/bootstrap && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/ansible-galaxy collection install -p /tmp/bootstrap/collections -r ubuntu_desktop/requirements.yml
```

Binding `/home` stops the desktop session - and the terminal you type in -
so the run goes into a system unit that carries on without it:

```bash
sudo systemd-run --unit=desktop-data --collect --working-directory=/tmp/bootstrap/ubuntu_desktop --setenv=ANSIBLE_COLLECTIONS_PATH=/tmp/bootstrap/collections /tmp/bootstrap/.venv/bin/ansible-playbook site.yml --tags data
```

It formats the data disk only if it is completely blank, mounts it at
`/mnt/data`, and binds `/mnt/data/home` over `/home`; the desktop logs in
again by itself. `journalctl -u desktop-data` shows how it went.

- **A rebuilt VM** gets its old `/home` back, with the repo, the state and
  the secrets in `~/Desktop/ProxmoxHomeLab`.
- **A first build** gets an empty one: clone the repo to
  `~/Desktop/ProxmoxHomeLab` and set it up as in the top-level README,
  "Setting up the controller".

Then `sudo rm -rf /tmp/bootstrap`. The old `/home` stays underneath the bind
mount, on the OS disk; to free that space:

```bash
sudo mkdir /tmp/rootview && sudo mount --bind / /tmp/rootview
sudo find /tmp/rootview/home -mindepth 1 -maxdepth 1 -exec rm -rf {} +
sudo umount /tmp/rootview && sudo rmdir /tmp/rootview
```

### 4. Apply the rest and reboot

From `~/Desktop/ProxmoxHomeLab/ubuntu_desktop`, with the venv active:

```bash
ansible-playbook site.yml
```

It installs the packages (the NVIDIA 595 driver, Terraform among them), the
snaps, the GNOME defaults and the network profile. Reboot once: the NVIDIA
driver, the PRIME profile and the static address take effect at boot. Then:

```bash
ip -br addr show enp6s18                  # 192.168.1.202/24
ip route get 10.10.10.1                   # via 192.168.1.201
ssh root@192.168.1.200 pveversion         # the host, with the controller's key
```

## Moving it to another network

The address lives in the guest and the bridge in Terraform, and the VM is the
controller: changing both from inside it would cut it off halfway. So:

1. Set the new address in `host_vars/desktop.yml` and the new bridge in
   `terraform/main.tf`.
2. `ansible-playbook site.yml --tags network` writes the profile; it takes
   effect at the next boot.
3. On the host, stop the VM, move its NIC, start it again - from the
   controller, as one detached job that outlives the VM's shutdown:

   ```bash
   ssh root@192.168.1.200 "systemd-run --unit=move-desktop --collect sh -c 'qm shutdown 102 --timeout 180 && qm set 102 --net0 virtio=BC:24:11:B8:0E:F8,bridge=NEWBRIDGE,firewall=0 && qm start 102'"
   ```

4. Back on the desktop, `terraform plan -var-file=secret.tfvars` in
   `terraform/` must show no changes.

## Rebuilding the VM

When the OS is beyond repair, replace VM 102 - its data disk stays. Not from
the desktop itself: the run would destroy the machine it runs on. From
another Linux machine with this repo, Terraform and a copy of
`terraform/terraform.tfstate` and `secret.tfvars`, in `terraform/`:

```bash
terraform apply -var-file=secret.tfvars -replace=proxmox_virtual_environment_vm.desktop
```

Then steps [3](#3-bring-home-back) and [4](#4-apply-the-rest-and-reboot):
the old `/home` comes back with the repo. Its `terraform.tfstate` is from
before the rebuild - copy the other machine's over it.
