# OPNsense bootstrap

The firewall VM (VM 100, `opnsense-fw`) from nothing to a configured firewall:
the VM, the interactive install, the interface assignment, the settings the API
cannot write, the API key, and the playbook that applies everything else. The
design and the rules it ends up with are in [docs/network.md](docs/network.md).

Before you start: the host is converged ([proxmox-bootstrap.md](proxmox-bootstrap.md)),
so `vmbr1`-`vmbr3` exist, and Terraform is initialised with `secret.tfvars` in
place. The next step after this one is
[ubuntu-desktop-bootstrap.md](ubuntu-desktop-bootstrap.md).

## 1. Create the VM with its WAN unplugged

> **The WAN interface has to start unplugged.** A fresh OPNsense applies a
> factory configuration of `LAN = 192.168.1.1/24` with a DHCP server. This home
> network already uses 192.168.1.0/24, so the moment that configuration touches
> `vmbr0` the VM answers ARP for the real router's address and hands out its own
> leases - the whole house loses internet, not just the lab. It happened here
> on 2026-09-09.

From `terraform/environments/production/`, without the desktop, which needs the
firewall as its gateway:

```bash
terraform apply -var-file=secret.tfvars -var firewall_wan_connected=false -var create_desktop=false
```

Proxmox downloads the installer ISO itself and creates the VM with four NICs,
in this fixed order:

| Proxmox | OPNsense | Bridge | Role |
|---|---|---|---|
| net0 | `vtnet0` | `vmbr0` | WAN, the home network (starts disconnected) |
| net1 | `vtnet1` | `vmbr1` | LAN |
| net2 | `vtnet2` | `vmbr2` | DMZ |
| net3 | `vtnet3` | `vmbr3` | LAB |

`terraform output opnsense_interface_map` prints the same table.

## 2. Install to disk

Open the VM's console in the Proxmox UI (`https://192.168.1.200:8006`,
`opnsense-fw` → Console).

1. The installer boots into a live environment. If the console menu is showing,
   choose **0) Logout**.
2. Log in as **`installer`** with password **`opnsense`**.
3. Follow the guided install onto the VM's disk (the defaults are fine), set
   the root password, and reboot. The disk is first in the boot order, so the
   VM now boots the installed system rather than the ISO.

## 3. Assign the interfaces

At the console menu choose **1) Assign interfaces**. Decline LAGG and VLAN
setup, then assign:

| Prompt | Answer |
|---|---|
| WAN | `vtnet0` |
| LAN | `vtnet1` |
| Optional 1 | `vtnet2` |
| Optional 2 | `vtnet3` |

OPNsense calls them `wan`, `lan`, `opt1` and `opt2`; the Ansible role maps
DMZ to `opt1` and LAB to `opt2`.

## 4. Address the interfaces

Choose **2) Set interface IP address** for each interface:

| Interface | Address | Upstream gateway |
|---|---|---|
| WAN | `192.168.1.201/24` | `192.168.1.1` |
| LAN | `10.10.10.1/24` | none |
| OPT1 (DMZ) | `10.10.20.1/24` | none |
| OPT2 (LAB) | `10.10.30.1/24` | none |

For WAN the prompts go:

- *Configure IPv4 address WAN interface via DHCP?* **n**
- address **192.168.1.201**, subnet bit count **24**, upstream gateway
  **192.168.1.1** (the console names it `WAN_GW`)
- *Use the gateway as the IPv4 name server, too?* **y**
- *Configure IPv6 address WAN interface via DHCP6?* **n**
- *Revert to HTTP as the web GUI protocol?* **n**

Say no to a DHCP server on every interface: Dnsmasq's pools are configured by
the playbook later.

## 5. Plug the WAN in

Now that WAN is `192.168.1.201` and not `192.168.1.1`, connect it.
`firewall_wan_connected` defaults to `true`, so a plain apply does it:

```bash
terraform apply -var-file=secret.tfvars -var create_desktop=false
```

## 6. Into the web UI the first time

This is the one awkward step. OPNsense's anti-lockout rule exists on LAN only,
and nothing is on the LAN segment yet, while WAN blocks everything inbound. So
the UI is reachable from neither side.

At the console choose **8) Shell** and disable the packet filter until the
next reboot:

```
pfctl -d
```

Browse to **`https://192.168.1.201`** from the home network and log in as
`root`. Skip or finish the setup wizard, then set what the API cannot write:

| Where | Setting | Value |
|---|---|---|
| System → Settings → General | Hostname / Domain | `OPNsense` / `internal` |
| System → Settings → General | Time zone | `Etc/UTC` |
| System → Settings → General | DNS servers | `192.168.1.1` |
| System → Settings → General | Allow DNS server list to be overridden by DHCP/PPP on WAN | on |
| System → Settings → Administration | Secure Shell: enabled, root login, password login | on |
| Interfaces → WAN | Block private networks | **off** |
| Interfaces → WAN | Block bogon networks | on |

*Block private networks* must stay off in this topology: WAN **is** the home
network, and that checkbox drops it with a quick rule ahead of every WAN pass
rule, locking every home-network client out of the firewall.

Every run of the playbook reads the interface assignment and addresses, the
`WAN_GW` gateway, the WAN block flags, the hostname and the running services
(sshd, Unbound, Dnsmasq) back, and stops before writing anything if one differs
from `opnsense_baseline_*` in `ansible/roles/opnsense_config/defaults/main.yml`.

## 7. Create the API key

**System → Access → Users → root → edit → API keys → +**. The browser downloads
a file with a `key` and a `secret`. Put both into `.env` at the repo root
(start from `.env.example`), under exactly these names:

```ini
OPNSENSE_API_KEY=...
OPNSENSE_API_SECRET=...
```

The role reads them as environment variables, so they never reach a disk or a
command line. Delete the downloaded file afterwards.

## 8. Apply the configuration

From `ansible/`, with the venv active. The dry run is a real difference report:
the baseline checks are reads, and the modules compare without writing.

```bash
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml --check --diff
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml
```

The `env $(grep ...)` prefix puts the two values into this one run only. Do not
`source` `.env`: its other values may hold characters the shell acts on.

The run writes the aliases, every filter rule, the Unbound forwarder, the
Dnsmasq listen settings, the DHCP pools and the desktop's DHCP reservation.
Then turn the packet filter back on - at the console, `pfctl -e`, or reboot the
VM. WAN sequence 10 keeps the web UI reachable from the home network from now
on.

Run the dry run again: it should report `changed=0`.

## 9. Check it

The checks are in [docs/network.md, "Verifying it actually works"](docs/network.md#verifying-it-actually-works).
From the controller, with the route in place (README, "Controller setup"):

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://192.168.1.201    # 200: the web UI
ping -c1 10.10.10.1                                                 # the LAN gateway
```

Before every later real run, take a configuration backup (System →
Configuration → Backups). OPNsense 26.7 has no savepoint API, so a run cannot
roll itself back.

## Troubleshooting

**The firewall is unreachable after a reboot, although its address is right.**
Proxmox may have the WAN "cable" unplugged (`link_down=1` on net0). Terraform
does that whenever it applies with `firewall_wan_connected=false`. Apply again
without that variable, or on the host:

```bash
qm config 100 | grep ^net0
qm set 100 -net0 virtio=02:7A:AA:5D:AD:51,bridge=vmbr0,firewall=0,link_down=0
```

**Locked out of the web UI.** Use the console through the Proxmox UI: **8)
Shell**, `pfctl -d`, fix the rule, `pfctl -e`. Nothing about recovering the
firewall depends on the firewall; docs/network.md, "When the firewall is down",
has the other ways in.

**The playbook fails with "malformed chunk footer".** OPNsense 26.7.0 corrupted
large HTTP/1.1 responses. Update the firewall to 26.7.1 or later.
