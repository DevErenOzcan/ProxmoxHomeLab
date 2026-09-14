# Proxmox IaC Homelab

Infrastructure-as-code for a Proxmox homelab. The host's OS-level state is
managed with **Ansible**; the virtual machines are managed with **Terraform**.

Target host: `pve1` — `192.168.1.200` (Proxmox VE 9 / Debian 13 trixie,
AMD Ryzen 7 5800H laptop).

---

## Architecture: why it works this way

Development and execution happen on your local machine (WSL, Git Bash, Linux, or macOS). Ansible and Terraform connect directly to the Proxmox host to apply the configuration.

```
Local Machine (WSL/Linux)        Proxmox host (192.168.1.200)
─────────────────────────        ────────────────────────────
run_ansible.sh           ──SSH─▶ configures the host OS (connection: remote)
run_terraform.sh         ──API─▶ provisions guests via Proxmox API
```

| Script | Drives | Applies |
|---|---|---|
| `./run_ansible.sh` | Ansible | Host OS state & Guest VM configurations |
| `./run_terraform.sh` | Terraform | Guests: the firewall VM and the VMs behind it |

---

## Quick start

### 1. Prerequisites

**Terraform**, and a POSIX shell to drive Ansible from: WSL, Linux or macOS.
Ansible has no native Windows control node, and a virtualenv created from
Windows (`Scripts/python.exe`) is useless here - make it from inside WSL.

Ansible itself is *not* installed system-wide. The repo carries its own
controller environment in `.venv`, pinned by `ansible/requirements.txt`
(ansible-core plus the API libraries) and `ansible/requirements.yml` (Galaxy
collections):

```bash
./run_ansible.sh --setup
```

That creates `.venv` when missing and fills it from both requirements files.
It is idempotent - re-run it whenever either file changes.

Copy `.env.example` to `.env`; `run_ansible.sh` exports it into every run,
which is how the OPNsense API credentials reach the firewall role.

Ensure you have passwordless SSH access to the Proxmox host (`192.168.1.200`) as `root` from your local machine.

### 2. Execution Steps

The repository is structured around independent environments. All execution commands (Ansible playbooks and Terraform commands) are documented in **[commands.md](commands.md)**. 

Please refer to that file to run the 3-step provisioning and configuration process.

---

## Layout

The project structure strictly follows DevOps best practices, clearly separating the logic for each VM:

```
commands.md                  Cheatsheet for execution commands

terraform/
  environments/
    production/              Live environment
  modules/                   Reusable infrastructure blocks
    opnsense/
    ubuntu_desktop/          Includes detached Data Volume support
    ubuntu_cloud/

ansible/
  ansible.cfg                Central config
  inventories/
    production/
      hosts.yml              All IPs and groups
      group_vars/            Variables separated by VM group
  roles/                     Shared tasks
    desktop_data_volume/     Handles formatting and mounting
    pve_common/
    network_bridge/
  playbooks/                 VM-specific playbooks
    proxmox/
      site.yml
    opnsense/
      site.yml
    ubuntu_desktop/
      10-base.yml
      site.yml
```

The network design, the firewall rules and the OPNsense post-install runbook
live in [docs/network.md](docs/network.md). Read that before the first
`terraform apply`.

[docs/commands.md](docs/commands.md) is a cheatsheet of the ~20 raw Ansible and
Terraform commands, for running the tools directly on the host instead of
through the wrappers.

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
| `[10/10]` unconditional reboot | `99-reboot.yml` | only when a reboot is actually pending |

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
- **Rebooting is conditional.** The old script ended with an unconditional
  `reboot` on every run. Now it happens only when `/run/reboot-required` is
  present, so re-running the playbook on a converged host is a no-op.

---

## Settings

Everything you would change lives in
`ansible/inventory/group_vars/proxmox_nodes.yml`. The ones touched most often:

```yaml
gpu_passthrough_pci_ids:        # [vendor:device] pairs from lspci -nn
  - "10de:25a0"                 # NVIDIA RTX 3050 Ti Mobile
  - "1002:1638"                 # AMD Cezanne iGPU

gpu_passthrough_grub_cmdline: "quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"

network_bridges:                # LAN / DMZ / LAB - see docs/network.md
  - name: vmbr1                 # LAN 10.10.10.0/24, trusted guests
    ports: "none"
    stp: "off"                  # quotes matter: YAML turns off/on/no/yes into booleans
  - name: vmbr2                 # DMZ 10.10.20.0/24, Cloudflare-facing + cloudflared
    ports: "none"
    stp: "off"
  - name: vmbr3                 # LAB 10.10.30.0/24, experiments and quarantine
    ports: "none"
    stp: "off"

base_packages_dist_upgrade: true
terraform_install: true
vendor_reset_enabled: true
laptop_lid_action: "ignore"
pve_reboot_after_converge: true    # reboot when one is pending
```

To disable a role entirely: `gpu_passthrough_enabled: false`,
`vendor_reset_enabled: false`, `network_bridge_enabled: false`,
`laptop_lid_enabled: false`.

---

## The firewall and the guests, with Terraform

Everything the guests do routes through an OPNsense firewall on its own VM.
The host itself stays on the home network so a broken firewall never costs you
the Proxmox UI. Full design, firewall rules and post-install steps:
**[docs/network.md](docs/network.md)**.

Order matters, because the bridges are host state and the guests need a
gateway that exists:

```bash
./state_push_ansible.sh --tags base,network
```

```bash
./state_push_terraform.sh
```

That creates the OPNsense ISO download and the firewall VM, and nothing else.
Install OPNsense from the Proxmox console, follow docs/network.md, add the one
static route it tells you to, and only then:

```bash
./state_push_terraform.sh --guests
```

`terraform output` prints the interface map, every address and the static route
line, so none of it has to be memorised.

The Windows guest is skipped unless you set `windows_11_iso_url` - Microsoft's
evaluation links expire about 24 hours after they are issued, so no committed
default can work.

---

## Known gotchas

- **The controller lives in `.venv`, and `run_ansible.sh` is the only way into
  it.** Two reasons that is a script rather than a documented command. First,
  apt's `/usr/bin/ansible` starts with the absolute shebang
  `#!/usr/bin/python3`, so *activating* a virtualenv cannot change which
  interpreter ansible imports from - it would keep reading
  `/usr/lib/python3/dist-packages` and never see `.venv`. Only
  `.venv/bin/ansible-playbook` runs in the venv. Second, `/mnt/c` is world
  writable, so ansible refuses an `ansible.cfg` found there and runs with no
  inventory, no `roles_path` and no pipelining; naming the file in
  `ANSIBLE_CONFIG` is the way out. The wrapper sets both and `cd`s into
  `ansible/`, because the config's paths are relative to it.
- **Which python executes a module is decided per group.** `proxmox_nodes`
  pins the *target's* `/usr/bin/python3`. The `opnsense` group runs on the
  *controller* - the ansibleguy modules call the REST API, so
  `playbooks/opnsense/site.yml` uses `connection: local` - and pins
  `{{ ansible_playbook_python }}`: the venv when started from here, the host's
  `python3` when `50-firewall-config.yml` drives the same role from pve1.
  Never hardcode the `.venv` path in inventory; it does not exist on the host.
- **CRLF.** The repo is edited on Windows and runs on Linux. `.gitattributes`
  keeps the working tree LF (`* text=auto eol=lf`), which matters most for
  `run_ansible.sh` and anything else shipped to a Linux box: a `\r` in the
  shebang line fails with "bad interpreter: ^M".
- **The `find` module's `contains` pattern** is anchored at the start of the
  line (it is not a plain `re.search`). That is why the pattern in `pve_repos`
  is written as `.*enterprise[.]proxmox[.]com.*`.
- **`ansible_managed` only exists in the `template` module**, not in `copy`.
  Tasks that use `copy` write a plain-text header instead. The variable itself
  is defined in `group_vars` rather than `ansible.cfg`, because the
  `ansible.cfg` setting is deprecated in ansible-core 2.19 and is removed in
  2.23 - the pinned core is 2.21.4, i.e. past the deprecation and before the
  removal.
- **What `--check` cannot tell you.** In a dry run the repositories are never
  actually written to disk, so PVE and HashiCorp packages do not appear in the
  APT cache. The `base_packages` and `terraform` roles detect this and print an
  explanatory note instead of failing.
