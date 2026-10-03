# Proxmox host bootstrap

From a blank laptop to a configured Proxmox host: repositories, packages,
storage, the guest bridges, GPU passthrough and vendor-reset. The next step
after this one is [opnsense-bootstrap.md](opnsense-bootstrap.md).

Before you start, set up the controller as described in the README
([Controller setup](README.md#controller-setup)).

## 1. Firmware

In the laptop's firmware setup, turn on CPU virtualization (AMD SVM) and the
IOMMU. GPU passthrough needs both; without the IOMMU, `30-gpu.yml` still
configures everything, but VM 102 will not start.

## 2. Install Proxmox VE

Boot the Proxmox VE 9 installer and answer:

| Prompt | Answer |
|---|---|
| Target disk | the **Samsung 512 GB (`nvme1n1`)**, ext4 |
| Hostname | `proxmox` - the node name Terraform's `node_name` expects |
| Management interface | `nic0` (Realtek RTL8111), the only wired NIC |
| IP address | `192.168.1.200/24` |
| Gateway / DNS | `192.168.1.1` / `192.168.1.1` |

> **Leave the Intel 670p (`nvme0n1`) alone.** It is not host storage: Terraform
> passes the whole disk to VM 102 as its data disk, and it carries that
> machine's data. Never select it in the installer and never add it to
> `storage.cfg`.

The installer's defaults create `local` (directory) and `local-lvm` (thin
pool) on `nvme1n1`; the code assumes exactly those two.

## 3. Let the controller in

From the controller, once (it asks for the root password you set):

```bash
ssh-copy-id root@192.168.1.200
ssh root@192.168.1.200 pveversion
```

`ansible/inventories/production/hosts.yml` reaches the host as `root` on
`192.168.1.200` with that key.

## 4. Converge the host

From `ansible/`, with the venv active. Look first; nothing is written:

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/proxmox/site.yml --check --diff
```

On a fresh install the dry run reports most tasks as changed, and the
`base_packages` and `vendor_reset` roles print notes rather than fail: in a dry
run the repositories are never written, so their packages look missing.

Then apply, in two steps. Repositories and packages first, because
vendor-reset's DKMS build needs the kernel headers they bring:

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/proxmox/site.yml --tags base
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/proxmox/site.yml
```

The full run writes the kernel command line, the VFIO and blacklist files,
builds vendor-reset, creates `vmbr1`-`vmbr3` and the guest isolation rules,
and adds `import` to the content types of `local`. Because GRUB and the
initramfs changed, the last play schedules a reboot one minute later. Cancel it
with `shutdown -c` on the host if you need to, or run with
`-e pve_reboot_after_converge=false` and reboot yourself.

What the run uses is in
`ansible/inventories/production/group_vars/proxmox_nodes.yml`. On different
hardware, replace `gpu_passthrough_pci_ids` (the `[vendor:device]` pairs from
`lspci -nn`) and `gpu_passthrough_grub_cmdline` first.

## 5. Check it

On the host, after the reboot:

```bash
grep -o 'amd_iommu=on iommu=pt' /proc/cmdline
lspci -nnk -s 01:00.0 | grep 'driver in use'      # vfio-pci
lspci -nnk -s 06:00.0 | grep 'driver in use'      # vfio-pci
dkms status -m vendor-reset                       # installed for the running kernel
ip -br link show type bridge                      # vmbr0 to vmbr3
nft list table bridge guest_isolation             # two drop rules, vmbr2 and vmbr3
pvesm status                                      # local and local-lvm, nothing on nvme0n1
```

A second run of the playbook should then report nothing to change, apart from
the dist-upgrade whenever new packages are out.

## 6. Prepare Terraform

From `terraform/environments/production/`:

```bash
cp secret.tfvars.example secret.tfvars      # then put root's password in it
terraform init
terraform plan -var-file=secret.tfvars
```

Terraform talks to the Proxmox API at `https://192.168.1.200:8006` as
`root@pam`. On an empty host the plan creates the OPNsense ISO download, the
firewall VM, the desktop image and the desktop VM - do not apply it as is:
[opnsense-bootstrap.md](opnsense-bootstrap.md) creates the firewall first, with
its WAN unplugged.
