# Cheatsheet

Both tools run **on the host**. Get there and pick a directory first.

```bash
ssh root@192.168.1.200
```

| # | Purpose | Command |
|---|---|---|
| 1 | Push local edits (from WSL, in the repo root) | `rsync -a --delete --exclude='.terraform*' --exclude='*.tfstate*' ansible terraform root@192.168.1.200:/opt/proxmox-homelab/` |

## Ansible — `cd /opt/proxmox-homelab/ansible`

| # | Purpose | Command |
|---|---|---|
| 2 | Dry run, changes nothing | `ansible-playbook site.yml --check --diff` |
| 3 | Apply everything | `ansible-playbook site.yml` |
| 4 | Apply, but do not reboot | `ansible-playbook site.yml -e pve_reboot_after_converge=false` |
| 5 | Apply one area | `ansible-playbook site.yml --tags network` |
| 6 | Skip one area | `ansible-playbook site.yml --skip-tags gpu` |
| 7 | What tags exist | `ansible-playbook site.yml --list-tags` |
| 8 | What is this variable set to | `ansible pve1 -m debug -a "var=gpu_passthrough_pci_ids"` |

Tags: `base` `repos` `packages` `terraform` `storage` `network` `gpu` `passthrough` `vendor_reset` `laptop` `lid`

`gpu` reboots the host (initramfs). So does `base` if it pulls a new kernel.
Settings live in `inventory/group_vars/proxmox_nodes.yml`.

## Terraform — `cd /opt/proxmox-homelab/terraform/environments/local`

Two variables have no defaults, so once per shell:

```bash
export TF_VAR_proxmox_endpoint=https://127.0.0.1:8006/
read -rsp 'Password: ' TF_VAR_proxmox_password; echo; export TF_VAR_proxmox_password
```

| # | Purpose | Command |
|---|---|---|
| 9 | After changing a module or provider | `terraform init` |
| 10 | What would change | `terraform plan` |
| 11 | Apply | `terraform apply` |
| 12 | Only the firewall | `terraform apply -target=module.firewall` |
| 13 | Plug the firewall's WAN in | `terraform apply -var firewall_wan_connected=true` |
| 14 | Firewall only, no guests | `terraform apply -var create_guests=false` |
| 15 | Addresses, routes, interface map | `terraform output` |
| 16 | What is managed | `terraform state list` |
| 17 | Rebuild one VM from scratch | `terraform apply -replace=module.firewall.proxmox_virtual_environment_vm.opnsense` |
| 18 | Delete one guest | `terraform destroy -target=module.ubuntu_server_vm` |

`-var` is not remembered. The next bare `apply` goes back to the default — for
`firewall_wan_connected` that unplugs the WAN again. Change `variables.tf` to
make it stick.

## Checking the result

| # | Purpose | Command |
|---|---|---|
| 19 | Guests and their state | `qm list` |
| 20 | One VM's config (NICs, disks, boot order) | `qm config 100` |
| 21 | Has a VM's disk been written to (0.00% = empty) | `lvs -o lv_name,data_percent pve/vm-100-disk-0` |
| 22 | vendor-reset per kernel vs the running one | `dkms status -m vendor-reset; uname -r` |
| 23 | Bridges | `ip -br addr show` |
| 24 | Is a reboot pending | `ls -l /run/reboot-required` |
