# ProxmoxHomeLab

Infrastructure as code for a single-node Proxmox homelab on a laptop. Ansible
configures the host, Terraform creates the virtual machines, and an OPNsense
firewall VM - itself configured over its REST API - stands between the guests
and the home network.

| Machine | Address | Defined by |
|---|---|---|
| `pve1`: Proxmox VE 9.2, node name `proxmox`, Ryzen 7 5800H laptop | 192.168.1.200 | `ansible/playbooks/proxmox` |
| VM 100 `opnsense-fw`: OPNsense 26.7 | 192.168.1.201 (WAN); 10.10.10.1, 10.10.20.1, 10.10.30.1 | `terraform/` + `ansible/playbooks/opnsense` |
| VM 102 `ubuntu-desktop`: Ubuntu 24.04 desktop, both GPUs passed through, `/home` on a 200 GB persistent disk | 10.10.10.11 | `terraform/` + `ansible/playbooks/ubuntu_desktop` |
| VM 110 `dmz-docker`: Ubuntu Server 26.04, Docker, its own Cloudflare Tunnel, Docker's state on a 50 GB persistent disk | 10.10.20.10 | `terraform/` + `ansible/playbooks/docker_hosts` |
| VMs 9102 `data-102`, 9110 `data-110`: only hold VM 102's and VM 110's data disks, never started | - | `terraform/` (`data_disks`) |

The firewall routes three internal segments: **LAN** (trusted, two-way with the
home network), **DMZ** (internet-facing services, internet only) and **LAB**
(experiments, internet only). The design and every firewall rule are in
[docs/network.md](docs/network.md); [docs/homelab-ag-haritasi.html](docs/homelab-ag-haritasi.html)
is an interactive map of the same network (in Turkish).

---

## How it is managed

Everything runs from one controller: WSL on the Windows workstation
(192.168.1.24). Nothing runs on the Proxmox host itself, and it holds no copy
of this repository.

```
controller (WSL)
  .venv/bin/ansible-playbook ──SSH──────▶ pve1            host OS
                             ──SSH──────▶ ubuntu-desktop  via the route 10.10.0.0/16 -> 192.168.1.201
                             ──SSH──────▶ dmz-docker      same route; WAN rule 13 lets only this machine in
                             ──HTTPS API▶ OPNsense        192.168.1.201
  terraform ─────────────────HTTPS API▶ pve1:8006       the VMs
```

| Tool | Run from | Applies |
|---|---|---|
| `ansible-playbook` (the repo's `.venv`) | `ansible/` | host OS state, the guests' in-guest state, the firewall's API configuration |
| `terraform` | `terraform/environments/production/` | the VMs and their data disks |

## Repository layout

```
README.md                      this file
proxmox-bootstrap.md           from a blank laptop to a configured host
opnsense-bootstrap.md          the firewall VM, its install and its API key
ubuntu-desktop-bootstrap.md    the GPU workstation VM
dmz-docker-bootstrap.md        the DMZ Docker host and its Cloudflare Tunnel
docs/
  network.md                   network design, firewall policy, verification
  homelab-ag-haritasi.html     interactive network map (Turkish)

ansible/
  ansible.cfg
  requirements.txt             the controller's Python packages (.venv)
  requirements.yml             the controller's Galaxy collections
  inventories/production/
    hosts.yml                  how to reach each machine
    group_vars/                one settings file per machine
  playbooks/
    proxmox/site.yml           10-base, 15-storage, 20-network, 30-gpu, 40-laptop, 99-reboot
    opnsense/site.yml
    ubuntu_desktop/site.yml
    docker_hosts/site.yml
  roles/
    pve_repos, base_packages, pve_storage, network_bridge,
    pve_common, gpu_passthrough, vendor_reset, laptop_lid    the Proxmox host
    opnsense_config                                           the firewall, over its REST API
    desktop_base, desktop_gnome                               the desktop
    docker_host                                               the Docker hosts
    data_volume                                               a guest's persistent data disk
  compose/<project>/           what the Docker hosts run, one compose.yaml each

terraform/
  environments/production/     the live environment: VMs 100, 102 and 110
  modules/
    opnsense/                  four NICs in a fixed order, WAN can start unplugged
    ubuntu_desktop/            q35 + OVMF, GPUs and USB ports passed through
    ubuntu_server/             a cloud-image guest; address and SSH key from cloud-init
    data_disk/                 a persistent data disk, owned by a never-started holder VM
```

---

## Controller setup

Once, in WSL (Ubuntu). A Windows checkout under `/mnt/c/...` is fine.

**Ansible.** It is not installed system-wide: the repo carries its own
controller environment in `.venv`, pinned by `ansible/requirements.txt` and
`ansible/requirements.yml`. From the repo root:

```bash
python3 -m venv .venv
.venv/bin/pip install -r ansible/requirements.txt
.venv/bin/ansible-galaxy collection install -r ansible/requirements.yml
```

Re-run the last two whenever either file changes. Activate the venv
(`. .venv/bin/activate`) before running any playbook. A venv created from
Windows (`Scripts/python.exe`) does not work: Ansible has no Windows control
node.

**Terraform** 1.5 or later, from HashiCorp's APT repository:

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform
```

**SSH key.** One key for every SSH target; its public half is in
`group_vars/ubuntu_desktop.yml`, in `ssh_public_keys` in
`terraform/environments/production/variables.tf` (cloud-init guests) and in
root's `authorized_keys` on pve1:

```bash
ssh-keygen -t ed25519 -C ansible-wsl
```

**The route into the segments.** The home router cannot hold a static route,
so the controller carries it. WSL shares the Windows routing table, so add it
on Windows, persistently (an elevated prompt):

```powershell
route -p add 10.10.0.0 mask 255.255.0.0 192.168.1.201
```

**Secrets**, both git-ignored:

| File | Holds | Start from |
|---|---|---|
| `.env` | `OPNSENSE_API_KEY`, `OPNSENSE_API_SECRET`, one `CLOUDFLARE_TUNNEL_TOKEN_<HOST>` per Docker host | `.env.example` |
| `terraform/environments/production/secret.tfvars` | `proxmox_password` (root@pam) | `secret.tfvars.example` |

Nothing loads `.env` by itself: the command lines below pass the values a
playbook needs into that one run.

---

## Building from scratch

In this order; each guide ends where the next one starts.

1. **[proxmox-bootstrap.md](proxmox-bootstrap.md)**: install Proxmox VE, then
   converge the host (repositories, bridges, vfio-pci, vendor-reset).
2. **[opnsense-bootstrap.md](opnsense-bootstrap.md)**: create the firewall VM
   with its WAN unplugged, install OPNsense, assign its interfaces, create the
   API key and apply the configuration.
3. **[ubuntu-desktop-bootstrap.md](ubuntu-desktop-bootstrap.md)**: create the
   desktop VM, give it SSH and apply its configuration.
4. **[dmz-docker-bootstrap.md](dmz-docker-bootstrap.md)**: let the workstation
   into the DMZ, create the Docker host, its Cloudflare Tunnel and its
   containers.

`terraform output next_steps` prints the same order.

---

## Day to day

Always look before you apply. From `ansible/`, with the venv active:

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/proxmox/site.yml --check --diff
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml --check --diff
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml --check --diff
env $(grep '^CLOUDFLARE_TUNNEL_TOKEN_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/docker_hosts/site.yml --check --diff
```

Drop `--check --diff` to apply. Narrow a run with `--tags`:

| Playbook | Tags |
|---|---|
| `proxmox/site.yml` | `base` repositories and packages · `storage` content types of "local", the `vmdata` storage · `network` bridges, their IPv6, guest isolation · `gpu` IOMMU, vfio-pci, vendor-reset · `laptop` lid switch |
| `ubuntu_desktop/site.yml` | `base` SSH key, APT repositories, packages, snaps, timezone, PRIME · `gnome` dconf defaults · `data` the data disk and `/home` on it |
| `docker_hosts/site.yml` | `data` the data disk at `/mnt/data` · `docker` Docker Engine and the compose projects |

Terraform, from `terraform/environments/production/`:

```bash
terraform plan -var-file=secret.tfvars
terraform apply -var-file=secret.tfvars
```

Before a real run, know what it does:

- **`proxmox/site.yml` dist-upgrades the host** and, when something left
  `/run/reboot-required` behind (a new kernel, GRUB, the initramfs), reboots it
  a minute later. Add `-e pve_reboot_after_converge=false` to keep it up.
- **`opnsense/site.yml` cannot roll back.** OPNsense 26.7 has no savepoint API;
  take a configuration backup first (System → Configuration → Backups).
- **Starting VM 102 takes the laptop's screen and keyboard.** SSH to the host
  keeps working.

---

## Where the settings live

| To change | Edit |
|---|---|
| The Proxmox host: bridges, vfio-pci IDs, kernel command line, storage | `ansible/inventories/production/group_vars/proxmox_nodes.yml`; everything not set there is a role default in `ansible/roles/<role>/defaults/main.yml` |
| The desktop: packages, snaps, GNOME, data volume | `ansible/inventories/production/group_vars/ubuntu_desktop.yml` |
| The Docker hosts: daemon settings, which projects run | `ansible/inventories/production/group_vars/docker_hosts.yml`; the projects themselves in `ansible/compose/<name>/` |
| The firewall: aliases, rules, DNS, DHCP | `ansible/roles/opnsense_config/defaults/main.yml` |
| The VMs: sizes, NICs, passthrough devices | `terraform/modules/<vm>/variables.tf`; addresses and segments in `terraform/environments/production/locals.tf` |
| A VM's persistent data disk | `data_disks` in `terraform/environments/production/variables.tf`: VM ID => size in GB, then pass `module.data_disk["<id>"].disk` to the VM |

Turn a host role off with `gpu_passthrough_enabled`, `vendor_reset_enabled`,
`network_bridge_enabled` or `laptop_lid_enabled: false` in
`group_vars/proxmox_nodes.yml`.

---

## Gotchas

- **`ANSIBLE_CONFIG=ansible.cfg` is not optional under `/mnt/c`.** That mount
  is world-writable, so Ansible ignores an `ansible.cfg` found there and runs
  with no inventory and no `roles_path` (every role "not found"). Naming the
  file bypasses the check; `cd ansible/` first, because its paths are relative.
  The permanent fix is `options = "metadata,umask=22,fmask=111"` under
  `[automount]` in `/etc/wsl.conf`, then `wsl --shutdown`.
- **Outside the venv you get apt's Ansible.** `/usr/bin/ansible-playbook`
  starts with `#!/usr/bin/python3` and cannot see `.venv`, including `httpx`,
  without which the firewall role fails.
- **The firewall play runs on the controller.** The ansibleguy modules call the
  REST API, so `opnsense/site.yml` uses `connection: local` and the `opnsense`
  group's interpreter is `{{ ansible_playbook_python }}`, the venv's. Never
  hardcode the `.venv` path in the inventory.
- **Do not set `ansible_managed`.** The files the GPU templates wrote on the
  host carry the default header, `# Ansible managed`. A different header
  rewrites all three, which rebuilds the initramfs and reboots the host for a
  comment.
- **What `--check` cannot tell you.** Repositories are never written in a dry
  run, so packages from them look missing; the roles print a note instead of
  failing. `pve_repos` reports the no-subscription repository and an APT cache
  refresh as changed even when the file on the host is identical, and
  `desktop_base` reports Docker's signing key whenever the server answers 200.
  `vendor_reset` reports "changed" on purpose when the module is not built for
  the running kernel.
- **The `find` module's `contains` is anchored at the line start**, which is
  why `pve_repos` matches `.*enterprise[.]proxmox[.]com.*`.
- **Facts are only under `ansible_facts`.** `inject_facts_as_vars` is off, as
  it will be by default from ansible-core 2.24: write
  `ansible_facts['kernel']`, not `ansible_kernel`.
- **CRLF.** The repo is edited on Windows and runs on Linux; `.gitattributes`
  keeps the working tree LF (`* text=auto eol=lf`).
- **bpg/proxmox reads absent keys as fixed values.** A VM edited in the GUI
  plans with zero diff only when the code states exactly those values; the
  comments at the top of `terraform/modules/ubuntu_desktop/main.tf` list them.
  The provider also sees only `usb0`-`usb3`, so the desktop's eight USB ports
  are set at creation and ignored afterwards.

## Design notes

- **`pve-blacklist.conf` is left to PVE.** The GPU blacklist is its own file,
  and the role asserts PVE's `blacklist nvidiafb` line instead of overwriting
  the file.
- **No `vfio_virqfd`.** It was folded into `vfio` in kernel 6.2; listing it on
  this host's 7.0 kernels is a boot-time error.
- **No `proxmox-default-headers`.** It follows PVE's default kernel, not the
  one this host runs. `base_packages` derives `proxmox-headers-$(uname -r)` and
  the ABI meta package and installs whichever actually exist.
- **The initramfs is rebuilt once.** `gpu_passthrough` and `vendor_reset` share
  a play and notify the same handler in `pve_common`.
- **Rebooting is conditional.** Only when `/run/reboot-required` exists, so a
  converged host is a no-op.
- **The host has no address on the guest bridges, IPv6 included,** and DMZ/LAB
  guests cannot reach each other (`network_bridge`; docs/network.md).
- **Data disks outlive their VMs.** The second NVMe is `vmdata`, thick-LVM
  storage (`pve_storage`). Each disk on it is owned by a holder VM (9000 + the
  VM's ID) that is never started and carries Proxmox's protection flag, and is
  attached to its VM as `scsi1`. Proxmox frees only a VM's own disks when the
  VM is destroyed, so a VM can be rebuilt without losing its data
  (ubuntu-desktop-bootstrap.md, "Rebuilding the VM"). Each VM sees only its own
  disk, and `saferemove` zeroes a deleted one before its space is reused.
