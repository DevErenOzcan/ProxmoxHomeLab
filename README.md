# ProxmoxHomeLab

The Proxmox host and the desktop VM that manages it - as code.

| Directory | Machine | Managed with |
|---|---|---|
| [`host/`](host/README.md) | `pve1`: Proxmox VE 9 on a Ryzen 7 5800H laptop, `192.168.1.200` | Ansible |
| [`ubuntu_desktop/`](ubuntu_desktop/README.md) | VM 102 `ubuntu-desktop`: the GPU workstation and the controller, `192.168.1.202` | Ansible (on itself) and Terraform |

Everything that runs *on* the host besides the desktop - the OPNsense
firewall, the Samba domain controller and the rest - lives in the
**librenfra** repository. This one only prepares the host for them: storage,
the bridges `vmbr1`-`vmbr3` the firewall routes, GPU passthrough.

**Each directory stands on its own.** It has its own `ansible.cfg`,
inventory, settings and roles, and every command for that machine runs from
inside it. Nothing is shared between them.

```
host/                      cd host && ansible-playbook site.yml
  site.yml                   the playbook
  host_vars/pve1.yml         every setting for the machine
  inventory.yml              how to reach it
  roles/                     one role per concern
  README.md                  what it does, how to build it from nothing

ubuntu_desktop/            cd ubuntu_desktop && ansible-playbook site.yml
  site.yml, host_vars/desktop.yml, inventory.yml, roles/, README.md
  terraform/               cd ubuntu_desktop/terraform && terraform plan -var-file=secret.tfvars
```

## The controller

Everything is run from the `ubuntu-desktop` VM, on the home network next to
the host and outside the firewall. The repo is checked out in its `/home`,
which is on a persistent data disk, so the checkout, the Terraform state and
the secrets survive a rebuilt VM.

```
ubuntu-desktop (192.168.1.202)
  ansible-playbook ── SSH ─────▶ pve1 (192.168.1.200)    host/
                   ── local ───▶ itself                   ubuntu_desktop/
  terraform ──────── HTTPS ────▶ pve1:8006 (Proxmox API)  ubuntu_desktop/terraform/
```

### Setting up the controller

Once, from the repo root on the desktop. Ansible is not installed system-wide:
the repo has its own environment in `.venv`.

```bash
sudo apt install python3-venv
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Activate it (`. .venv/bin/activate`) before running anything. Each directory
lists the collections its roles need:

```bash
ansible-galaxy collection install -r host/requirements.yml -r ubuntu_desktop/requirements.yml
```

Terraform comes with the desktop's own packages (`ubuntu_desktop`, tag
`base`). The controller's SSH key, `~/.ssh/id_ed25519`, goes into root's
`authorized_keys` on the host (`ssh-copy-id root@192.168.1.200`), and the
host's root password into `ubuntu_desktop/terraform/secret.tfvars`.

### Secrets

Both stay on the controller and are git-ignored:

| File | Holds |
|---|---|
| `ubuntu_desktop/terraform/secret.tfvars` | the host's root password, for the Proxmox API |
| `ubuntu_desktop/terraform/terraform.tfstate` | what Terraform manages - not secret, but only here |

Keep a copy of both, and of `~/.ssh/id_ed25519`, off the laptop: the data
disk is persistent, not backed up.

## Order, from nothing

1. [host/README.md](host/README.md): install Proxmox VE and converge the host.
2. [ubuntu_desktop/README.md](ubuntu_desktop/README.md): create the desktop
   and make it the controller.
3. librenfra: the firewall and everything behind it.
