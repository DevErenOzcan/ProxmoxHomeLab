# Proxmox IaC Homelab

Infrastructure-as-code for a Proxmox homelab. The host's OS-level state is
managed with **Ansible**; the virtual machines are managed with **Terraform**.

Target host: `pve1` — `192.168.1.200` (Proxmox VE 9 / Debian 13 trixie,
AMD Ryzen 7 5800H laptop).

---

## Architecture: why it works this way

Development happens on Windows, but **Ansible cannot act as a control node on
Windows**. So the model is:

```
Windows (this repo)              Proxmox host (192.168.1.200)
───────────────────              ────────────────────────────
edit ansible/
        │
        │  ./sync.sh   (tar + ssh, single connection)
        ▼
                                 /opt/proxmox-homelab/ansible
                                         │
                                         │ ansible-playbook site.yml
                                         │ (connection: local)
                                         ▼
                                 the host configures itself
```

Ansible runs **on** the host. The Windows side only pushes files. The transfer
uses `tar | ssh` (no local `rsync` required) and the host side mirrors the tree
exactly with `rsync --delete`.

---

## Quick start

### 1. First-time setup (once)

```bash
./sync.sh --bootstrap
```

This pushes the files to the host, runs `bootstrap.sh` there, installs
`ansible-core`, places the state under `/opt/proxmox-homelab`, creates the
`pve-state` shortcut, and verifies `site.yml` syntax.

`bootstrap.sh` does **nothing else**. Repository fixes, GRUB, GPU, DKMS and lid
settings all live in Ansible roles now.

### 2. See what would change (changes nothing)

```bash
./sync.sh --check
```

### 3. Apply

```bash
./sync.sh --run
```

### 4. Reboot

A reboot is required when GRUB, kernel modules or the initramfs change. The
playbook never reboots on its own — it drops `/run/reboot-required` and warns:

```bash
./sync.sh --run -e pve_reboot_after_converge=true
```

---

## Day-to-day use

| Command | What it does |
|---|---|
| `./sync.sh` | Push only |
| `./sync.sh --check` | Push + dry run (`--check --diff`) |
| `./sync.sh --run` | Push + apply `site.yml` |
| `./sync.sh --run --tags gpu` | Extra arguments are passed to `ansible-playbook` |
| `./sync.sh --watch --check` | Push + dry run automatically on every change |
| `./sync.sh --shell` | Open a shell on the host (in `/opt/proxmox-homelab/ansible`) |
| `./sync.sh --install-key` | Set up key-based SSH so no password is needed (once) |

The same from PowerShell: `.\sync.ps1 --check` (it delegates to Git Bash).

On the host itself:

```bash
pve-state --check --diff      # dry run
pve-state                     # apply
pve-state --tags gpu          # one part only
```

### Live mirroring

`--watch` hashes the contents of `ansible/` every 2 seconds and pushes as soon
as anything changes:

```bash
./sync.sh --watch --check     # edit → save → see the plan
./sync.sh --watch --run       # edit → save → apply
```

Interval: `WATCH_INTERVAL=5 ./sync.sh --watch`.

### Settings

Override with environment variables:

```bash
PVE_HOST=192.168.1.201 ./sync.sh --check
STATE_DIR=/srv/homelab ./sync.sh
```

### Authentication

`sync.sh` tries an SSH key first. Without one it uses the `proxmox_passwd`
value from the repository's `.env` via `SSH_ASKPASS` — the password never
reaches the command line or `ps` output. `.env` is not committed.

To stop reading the password on every run, install a key:

```bash
./sync.sh --install-key
```

---

## Layout

```
bootstrap.sh                 Installs ansible on the host + places the state. Nothing else.
sync.sh                      Local → host transfer (--check / --run / --watch / --bootstrap)
sync.ps1                     PowerShell wrapper (delegates to sync.sh)
run_vms.sh                   Brings the VMs up with Terraform

ansible/
  ansible.cfg                Default inventory, roles_path
  site.yml                   Runs every playbook in order
  inventory/
    local.yml                DEFAULT — host configures itself (connection: local)
    remote.yml               From a Linux control machine over SSH
    group_vars/
      proxmox_nodes.yml      ⭐ THE settings file — everything you'd change is here
    host_vars/
      pve1.yml               Overrides that apply to pve1 only
  playbooks/
    10-base.yml              repositories + packages + terraform
    20-network.yml           the vmbr1 bridge
    30-gpu.yml               GPU passthrough + vendor-reset (one play on purpose)
    40-laptop.yml            lid behaviour
    99-reboot.yml            is a reboot needed / optional reboot
  roles/
    pve_common/              shared handlers (update-grub, initramfs, reboot marker)
    pve_repos/               disable enterprise repos, add no-subscription
    base_packages/           dist-upgrade, base packages, kernel header selection
    terraform/               HashiCorp repository + terraform package
    network_bridge/          vmbr1 (the Terraform modules attach to it)
    gpu_passthrough/         IOMMU + VFIO + blacklist + vfio-pci bind
    vendor_reset/            DKMS module for the AMD reset bug
    laptop_lid/              logind lid settings

terraform/
  environments/local/        Environment-specific main.tf / provider.tf / variables.tf
  modules/                   router, ubuntu_server, ubuntu_desktop, windows_11
```

> Why is `group_vars` under `inventory/`? The playbooks live in the
> `playbooks/` subdirectory, and Ansible looks for playbook-adjacent
> `group_vars` in `playbooks/group_vars/`. Inventory-adjacent `group_vars` are
> loaded no matter which playbook runs.

---

## Tags

```bash
pve-state --tags base       # repos + packages + terraform (no reboot implied)
pve-state --tags network    # vmbr1
pve-state --tags gpu        # passthrough + vendor-reset (needs a reboot)
pve-state --tags laptop     # lid settings
```

---

## What moved from bootstrap.sh into Ansible

| Old bootstrap step | New home | Note |
|---|---|---|
| `[1/10]` disable enterprise repo | `pve_repos` | deb822 `Enabled: false` instead of renaming `.list` |
| `[2/10]` dist-upgrade + packages | `base_packages` | picks kernel headers by querying the repos |
| `[3/10]` install Terraform | `terraform` | `/etc/apt/keyrings` instead of `apt-key` |
| `[4/10]` GRUB IOMMU | `gpu_passthrough` | |
| `[5/10]` VFIO modules | `gpu_passthrough` | `/etc/modules-load.d/` instead of `/etc/modules` |
| `[6/10]` GPU blacklist | `gpu_passthrough` | own file, does not overwrite PVE's |
| `[7/10]` vfio-pci bind | `gpu_passthrough` | |
| `[8/10]` vendor-reset DKMS | `vendor_reset` | skips the rebuild when already installed |
| `[9/10]` laptop lid | `laptop_lid` | `logind.conf.d/` drop-in |
| `[10/10]` unconditional reboot | `99-reboot.yml` | **off** by default, must be asked for |

Behaviours fixed along the way:

- **`pve-blacklist.conf` is no longer clobbered.** The old script overwrote
  PVE's own file, deleting the `blacklist nvidiafb` line it ships with. A
  separate file is used now, and if the old script ever ran, that line is put
  back.
- **`vfio_virqfd` was dropped from the module list.** It was folded into `vfio`
  in kernel 6.2; on this host (7.0.2-6-pve) no such module exists, and leaving
  it listed produces a boot-time error.
- **`proxmox-default-headers` is not used.** That meta package points at PVE's
  default kernel (6.14) while this host runs 7.0.2-6-pve — it would install the
  wrong headers and the DKMS build would fail. The role derives the exact
  running-kernel package (`proxmox-headers-7.0.2-6-pve`) and the ABI meta
  package (`proxmox-headers-7.0`), then installs whichever ones **actually
  exist** in the repositories.
- **`update-initramfs` runs once.** Both `gpu_passthrough` and `vendor_reset`
  notify it; the handler is defined once in `pve_common` and both roles share a
  single play, so the initramfs is rebuilt once instead of twice.
- **Rebooting is not automatic.** The old script ended with an unconditional
  `reboot`.

---

## Settings

Everything you would change lives in
`ansible/inventory/group_vars/proxmox_nodes.yml`. The ones touched most often:

```yaml
gpu_passthrough_pci_ids:        # [vendor:device] pairs from lspci -nn
  - "10de:25a0"                 # NVIDIA RTX 3050 Ti Mobile
  - "1002:1638"                 # AMD Cezanne iGPU

gpu_passthrough_grub_cmdline: "quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"

network_bridges:                # the Terraform VMs attach to vmbr1
  - name: vmbr1
    ports: "none"
    stp: "off"                  # quotes matter: YAML turns off/on/no/yes into booleans

base_packages_dist_upgrade: true
terraform_install: true
vendor_reset_enabled: true
laptop_lid_action: "ignore"
pve_reboot_after_converge: false
```

To disable a role entirely: `gpu_passthrough_enabled: false`,
`vendor_reset_enabled: false`, `network_bridge_enabled: false`,
`laptop_lid_enabled: false`.

---

## Virtual machines with Terraform

Once the host is ready (`pve-state` has run, and it has been rebooted if
needed), the VMs are created with Terraform.

```bash
cd terraform/environments/local
terraform init
terraform plan
terraform apply
```

Or in one command on the host:

```bash
/opt/proxmox-homelab/run_vms.sh
```

The Windows 11 ISO link in `main.tf` expires 24 hours after Microsoft issues
it; if the download fails, replace that URL with a fresh one.

---

## Known gotchas

- **CRLF.** The repo is edited on Windows and runs on Linux. `.gitattributes`
  keeps the working tree LF, and `sync.sh` additionally strips `\r` from
  `.yml/.yaml/.cfg/.j2/.sh/.md/.tf` files on the host.
- **The `find` module's `contains` pattern** is anchored at the start of the
  line (it is not a plain `re.search`). That is why the pattern in `pve_repos`
  is written as `.*enterprise[.]proxmox[.]com.*`.
- **`ansible_managed` only exists in the `template` module**, not in `copy`.
  Tasks that use `copy` write a plain-text header instead. The variable itself
  is defined in `group_vars` rather than `ansible.cfg`, because the
  `ansible.cfg` setting is deprecated in ansible-core 2.19 and is removed in
  2.23.
- **What `--check` cannot tell you.** In a dry run the repositories are never
  actually written to disk, so PVE and HashiCorp packages do not appear in the
  APT cache. The `base_packages` and `terraform` roles detect this and print an
  explanatory note instead of failing.
