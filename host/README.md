# host - the Proxmox server

`pve1`: Proxmox VE 9 on a Ryzen 7 5800H laptop, at `192.168.1.200` on the
home network, node name `proxmox`. This directory configures the host's own
operating system with Ansible; it creates no VMs.

| File | What it is |
|---|---|
| `site.yml` | the playbook: everything below, in order |
| `host_vars/pve1.yml` | every setting specific to this machine |
| `inventory.yml` | how the controller reaches it: `root@192.168.1.200` over SSH |
| `roles/` | one role per concern (table below) |
| `ansible.cfg`, `requirements.yml` | Ansible settings and the collections the roles need |

What the playbook sets up:

| Tag | Role | What it does |
|---|---|---|
| `base` | `pve_repos` | turns the enterprise repositories off and the no-subscription one on |
| `base` | `base_packages` | dist-upgrade, build tools, and the kernel headers of the *running* kernel |
| `storage` | `pve_storage` | `import` content on `local`; the second NVMe as thick-LVM storage `vmdata` |
| `network` | `network_bridge` | port-less bridges `vmbr1`-`vmbr3` for the firewall's segments, no host IPv6 on them, guests on `vmbr2`/`vmbr3` isolated from each other |
| `gpu` | `gpu_passthrough` | IOMMU on, both GPUs (and the Wi-Fi card) bound to `vfio-pci` |
| `gpu` | `vendor_reset` | the DKMS module that lets the AMD iGPU be reset between VM starts |
| `gpu` | `pve_common` | the GRUB/initramfs handlers both GPU roles share |
| `laptop` | `laptop_lid` | keeps the host running with the lid closed |

The last play reboots the host when a change needs it (below).

## Running it

From this directory, on the controller (the `ubuntu-desktop` VM), with the
repo's venv active:

```bash
ansible-playbook site.yml --check --diff
```

```bash
ansible-playbook site.yml
```

Look before you apply: `--check --diff` changes nothing and shows what would.
Limit a run with `--tags`, e.g. `--tags network`.

**A run can reboot the host.** When something leaves `/run/reboot-required`
behind - a new kernel from the dist-upgrade, GRUB, kernel modules, the
initramfs - the last play schedules a reboot one minute later. Every VM goes
down with it, **the controller included**: add
`-e pve_reboot_after_converge=false` and reboot when it suits you. A run that
changes none of those never reboots.

## Building it from nothing

### 1. Firmware

In the laptop's firmware setup, turn on CPU virtualization (AMD SVM) and the
IOMMU. GPU passthrough needs both; without the IOMMU, the `gpu` part still
configures everything, but the desktop VM will not start.

### 2. Install Proxmox VE

Boot the Proxmox VE 9 installer and answer:

| Prompt | Answer |
|---|---|
| Target disk | the **Samsung 512 GB**, ext4 |
| Hostname | `proxmox` - the node name the desktop's Terraform expects |
| Management interface | `nic0` (Realtek RTL8111), the only wired NIC |
| IP address | `192.168.1.200/24` |
| Gateway / DNS | `192.168.1.1` / `192.168.1.1` |

**Leave the Intel 670p out of the installer.** It becomes `vmdata` in
[step 5](#5-a-data-disk-for-the-vms) - and on a reinstalled host it already
carries the VMs' data disks, the desktop's `/home` among them.

### 3. Let the controller in

From the controller, once (it asks for the root password you set):

```bash
ssh-copy-id root@192.168.1.200
```

```bash
ssh root@192.168.1.200 pveversion
```

### 4. Converge the host

Look first:

```bash
ansible-playbook site.yml --check --diff
```

On a fresh install the dry run reports most tasks as changed, and
`base_packages` and `vendor_reset` print notes instead of failing: a dry run
never writes the repositories, so their packages look missing.

Then apply in two steps - repositories and packages first, because
vendor-reset's DKMS build needs the kernel headers they bring:

```bash
ansible-playbook site.yml --tags base
```

```bash
ansible-playbook site.yml
```

GRUB and the initramfs changed, so the host reboots a minute after the run.

On different hardware, change `host_vars/pve1.yml` first:
`gpu_passthrough_pci_ids` (the `[vendor:device]` pairs from `lspci -nn`),
`gpu_passthrough_grub_cmdline`, and the disk in `pve_storage_lvm`.

### 5. A data disk for the VMs

The Intel 670p becomes `vmdata`: one LVM volume group on the whole disk,
registered as Proxmox **thick-LVM** storage. Each VM's persistent data disk
is carved out of it and reserved in full, like a partition; a VM sees only
the disk attached to it, and `saferemove` zeroes a deleted disk before its
space is reused.

The `storage` tag creates it, and only on a disk that is blank or already
this volume group's - anything else on it stops the run, and the role never
wipes a disk. A disk that was used before needs a deliberate wipe first.
**Look at what is on it, then wipe only if it can go:**

```bash
lsblk -f /dev/disk/by-id/nvme-INTEL_SSDPEKNW512GZL_PHKA215401EP512A
```

```bash
wipefs -a /dev/disk/by-id/nvme-INTEL_SSDPEKNW512GZL_PHKA215401EP512A
```

(`wipefs` each partition first, then the disk.) Then:

```bash
ansible-playbook site.yml --tags storage
```

### 6. Check it

On the host, after the reboot:

```bash
grep -o 'amd_iommu=on iommu=pt' /proc/cmdline
lspci -nnk -s 01:00.0 | grep 'driver in use'      # vfio-pci
lspci -nnk -s 06:00.0 | grep 'driver in use'      # vfio-pci
dkms status -m vendor-reset                       # installed for the running kernel
ip -br link show type bridge                      # vmbr0 to vmbr3
nft list table bridge guest_isolation             # two drop rules, vmbr2 and vmbr3
pvesm status                                      # local, local-lvm and vmdata
```

A second `ansible-playbook site.yml` should report nothing to change, apart
from the dist-upgrade whenever new packages are out.

## Good to know

- **What `--check` cannot tell you.** Repositories are never written in a dry
  run, so packages from them look missing; the roles print a note instead of
  failing. `pve_repos` reports the no-subscription repository and an APT
  cache refresh as changed even when nothing differs, and `vendor_reset`
  reports "changed" on purpose when the module is not built for the running
  kernel.
- **Strings that land on the host are not cosmetic.** The bridge comments in
  `host_vars/pve1.yml` go into `/etc/network/interfaces`, and the roles'
  file headers into the files they write. Editing one rewrites the file on
  the next run - for the GPU files that means a new initramfs and a reboot.
  So do not set `ansible_managed` either: the GPU templates carry its default.
- **No `proxmox-default-headers`.** It follows PVE's default kernel, not the
  one running. `base_packages` installs `proxmox-headers-$(uname -r)` and the
  ABI meta package, whichever exist.
- **No `vfio_virqfd`.** It was folded into `vfio` in kernel 6.2; listing it
  on this host's 7.0 kernels is a boot-time error.
- **`pve-blacklist.conf` is left to PVE.** The GPU blacklist is its own file;
  the role only asserts PVE's `blacklist nvidiafb` line.
- **The host has no address on `vmbr1`-`vmbr3`, IPv6 link-local included.**
  sshd, pveproxy and rpcbind listen on every address, so a link-local one
  would let any guest reach the host without crossing the firewall.
- **The `find` module's `contains` is anchored at the line start**, which is
  why `pve_repos` matches `.*enterprise[.]proxmox[.]com.*`.
- **Facts are only under `ansible_facts`** (`inject_facts_as_vars` is off):
  write `ansible_facts['kernel']`, not `ansible_kernel`.
