# Network design

Everything the guests do goes through an OPNsense firewall. This document is
the design and the post-install runbook — the parts Terraform and Ansible
cannot do for you, because OPNsense has no unattended installer.

## The constraint that shapes everything

The host has **one** physical NIC (`nic0`, a Realtek RTL8111, in `vmbr0`). The
MediaTek MT7921 wireless card is in the PCI passthrough list
(`gpu_passthrough_pci_ids`), so it cannot carry host traffic either.

There is therefore no second uplink to put "outside" the firewall. The firewall
is **router-on-a-stick**: its WAN leg lives on the home network, and each
internal segment is a port-less Linux bridge that exists only inside the host.

```
internet ── home router (192.168.1.1)
                 │
                 │  192.168.1.0/24  ← home network, NOT behind the firewall
                 ├──────────── Proxmox host   192.168.1.200   (vmbr0)
                 │             stays here on purpose
                 │
                 └──────────── OPNsense WAN   192.168.1.201   (vmbr0, vtnet0)
                                     │
                 ┌───────────────────┼───────────────────┐
              vmbr1               vmbr2               vmbr3
              vtnet1              vtnet2              vtnet3
          LAN 10.10.10.1      DMZ 10.10.20.1      LAB 10.10.30.1
          trusted guests      Cloudflare-facing   experiments,
                              services +          quarantine
                              cloudflared
```

**The Proxmox host is deliberately not behind the firewall.** If it were, a
crashed or misconfigured firewall VM would take the Proxmox web UI with it, and
the only way back would be the laptop's own keyboard. Keeping the host on
`vmbr0` means the recovery console is always reachable at
`https://192.168.1.200:8006`.

The host has no address on `vmbr1`–`vmbr3`, IPv6 link-local included: the
`network_bridge` role sets `disable_ipv6` on them. sshd, pveproxy and rpcbind
listen on every address, so a link-local one would let any guest reach the
host's 22, 8006 and 111 without crossing the firewall.

## Why 10.10.x.x

All three internal segments sit inside one `10.10.0.0/16` supernet, so reaching
them from the home network needs **exactly one** static route instead of three:

```
10.10.0.0/16  →  192.168.1.201
```

The old flat `192.168.3.0/24` is gone.

## Address plan

| Segment | Bridge | Interface | Subnet | Gateway | Purpose |
|---|---|---|---|---|---|
| WAN | `vmbr0` | `vtnet0` | 192.168.1.0/24 | 192.168.1.1 | Faces the home network |
| LAN | `vmbr1` | `vtnet1` | 10.10.10.0/24 | 10.10.10.1 | Trusted guests |
| DMZ | `vmbr2` | `vtnet2` | 10.10.20.0/24 | 10.10.20.1 | Internet-facing services, cloudflared |
| LAB | `vmbr3` | `vtnet3` | 10.10.30.0/24 | 10.10.30.1 | Experiments, quarantine |

Reserved static addresses:

| Address | Host |
|---|---|
| 192.168.1.200 | Proxmox host |
| 192.168.1.201 | OPNsense WAN |
| 10.10.20.10 | cloudflared container (reserved, not built yet) |
| 10.10.10.11 | ubuntu-desktop (VM 102), DHCP reservation on `BC:24:11:B8:0E:F8` |

DHCP pools are `10.10.10.100-245` (LAN) and `10.10.30.100-199` (LAB) and are
for throwaway guests. The DMZ has no pool.

`terraform output` prints all of this, so you do not have to keep this table in
your head.

> Interface order matters. Proxmox maps `net0..net3` to FreeBSD
> `vtnet0..vtnet3` in order. Appending a NIC in
> `terraform/modules/opnsense/main.tf` is safe; **reordering** the
> `network_device` blocks silently rewires a running firewall.

## Order of operations

This is the order for building the network from scratch. Everything runs from
your own machine; the exact command lines are in [commands.md](../commands.md).

**1. Create the bridges** — host OS state, so this is Ansible's job:
`playbooks/proxmox/site.yml` (or just `--tags network`).

**2. Create the firewall VM, with its WAN unplugged** — and without the
desktop, which needs the firewall as its gateway:

```bash
terraform apply -var-file=secret.tfvars \
  -var firewall_wan_connected=false -var create_desktop=false
```

**3. Install and configure OPNsense** — the sections below. This part is
manual: OPNsense has no unattended installer.

**4. Add the static route** on the home router, or on each client.

**5. Apply the firewall configuration** — `playbooks/opnsense/site.yml`.

**6. Create the desktop** — a plain `terraform apply -var-file=secret.tfvars`.

## Installing OPNsense

> **The WAN interface starts unplugged, and it has to.** A fresh OPNsense
> applies a factory config of `LAN = 192.168.1.1/24` with a DHCP server on it.
> This home network already uses 192.168.1.0/24, so the moment that config
> touches `vmbr0` the VM starts answering ARP for the real router's address and
> serving its own leases — the whole house loses internet, not just the lab.
> That is not hypothetical; it happened here on 2026-09-09 and took the host's
> own DNS down with it.
>
> Pass `-var firewall_wan_connected=false` for the install, which sets
> `disconnected` on net0. Install and assign interfaces first, then connect it.
> The variable defaults to `true` only because the running firewall is
> installed - with `false`, an apply would unplug it.

Open the VM console in the Proxmox UI (`opnsense-fw` → Console).

1. The installer boots into a live environment. Log in as **`installer`** with
   password **`opnsense`**. Follow the guided install, then reboot.
2. At the console menu choose **1) Assign interfaces**. Decline LAGG and VLAN
   setup, then assign:

   | Prompt | Answer |
   |---|---|
   | WAN | `vtnet0` |
   | LAN | `vtnet1` |
   | Optional 1 | `vtnet2` |
   | Optional 2 | `vtnet3` |

3. Choose **2) Set interface IP address** and give each one its address from
   the table above. WAN is static `192.168.1.201/24` with gateway
   `192.168.1.1` (the console names that gateway `WAN_GW`); say no to DHCP on
   every interface for now; say no to IPv6.

4. Only now plug WAN in - a plain apply, since the variable defaults to
   `true`:

   ```bash
   terraform apply -var-file=secret.tfvars -var create_desktop=false
   ```

   Until this runs, the firewall can see its internal segments but not the home
   network — which is exactly what you want while it still thinks it is
   192.168.1.1.

5. Set what the API cannot. Each of these is read back by every run of
   `playbooks/opnsense/site.yml`, which stops before writing anything if one
   differs (`opnsense_baseline_*` in the role's defaults); the rest are the
   values the running firewall has:

   | Where | Setting | Value |
   |---|---|---|
   | System → Settings → General | Hostname / Domain | `OPNsense` / `internal` (checked) |
   | System → Settings → General | Time zone | `Etc/UTC` |
   | System → Settings → General | DNS servers | `192.168.1.1` |
   | System → Settings → General | Allow DNS server list to be overridden by DHCP/PPP on WAN | on |
   | System → Settings → Administration | Secure Shell: enabled, root login, password login | on (sshd running is checked) |
   | Interfaces → WAN | Block private networks | **off** (checked) |
   | Interfaces → WAN | Block bogon networks | on (checked) |
   | System → Access → Users → root | API key | the one `.env` holds |

   *Block private networks* has to stay off in this topology: WAN **is** the
   home network, and that checkbox drops it with a quick rule ahead of every
   WAN pass rule. It locked every home-network client out of the firewall on
   2026-09-17.

### Getting into the web UI the first time

This is the one genuinely awkward step. OPNsense creates an anti-lockout rule
on LAN only, and nothing is on the LAN segment yet — while the WAN interface
blocks all inbound traffic and has *Block private networks* enabled. So the UI
is reachable from neither side.

From the console menu pick **8) Shell** and disable the packet filter:

```
pfctl -d
```

Now browse to **`https://192.168.1.201`** from your own machine — that address
is on your own subnet, so no static route is needed yet. Log in as `root` /
`opnsense`, run the setup wizard, and add the rules below. Then re-enable the
filter (`pfctl -e`) or just reboot the VM; the WAN rule you added keeps the UI
reachable from then on.

## Firewall policy

The requirement is asymmetric: **guests must not reach the home network, but
you must be able to reach the guests.** A stateful firewall does exactly this —
you allow the inbound direction on WAN and block the outbound direction on each
internal interface. Replies flow on existing state, so nothing else is needed.

These tables are the rules the firewall runs (2026-10-03), one for one with
`opnsense_rules` in `ansible/roles/opnsense_config/defaults/main.yml`; `seq` is
the rule's sequence there. Two aliases keep them readable:

| Alias | Type | Content |
|---|---|---|
| `HOME_LAN` | Network(s) | `192.168.1.0/24` |
| `LAB_NETS` | Network(s) | `10.10.0.0/16` |

### WAN (`vtnet0`)

**Block private networks** stays off on this interface — otherwise nothing
from `192.168.1.0/24` is ever evaluated and the rules below never match.

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 10 | Pass | `HOME_LAN` | this firewall | TCP 443 | Reach this web UI from home |
| 11 | Pass | `HOME_LAN` | `LAB_NETS` | any | Reach the guests from home |
| 12 | Pass | `HOME_LAN` | this firewall | TCP 22 | SSH to the firewall from home |

Everything else inbound stays blocked by the implicit default. Nothing from the
internet can reach in at all — the home router forwards no ports.

### LAN (`vtnet1`)

The trusted segment. Every machine on it may reach the home network, the DMZ,
the LAB and the internet; traffic to the home network leaves NATed as
`192.168.1.201`. Together with WAN sequence 11 that makes LAN ↔ home two-way.
Nothing on the DMZ or LAB can open a connection into the LAN — their own
sequence 30 blocks `LAB_NETS`, which covers `10.10.10.0/24`.

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 1 | Pass | LAN net | any | any (IPv4) | Installer default |
| 10 | Pass | 10.10.10.0/24 | 10.10.10.1 | UDP 53 | DNS on the gateway |
| 11 | Pass | LAN net | any | any (IPv6) | Installer default |
| 40 | Pass | 10.10.10.0/24 | 10.10.20.0/24 | any | LAN may use DMZ services |
| 50 | Pass | 10.10.10.0/24 | any | any | Home network, LAB, internet |

Sequences 1 and 11 already say "anything", so 10, 40 and 50 change nothing
while they exist; they spell out the individual paths. The LAN once had block
rules at 20 (→ `HOME_LAN`) and 30 (→ LAB) that sat below sequence 1 and never
matched. They are listed in `opnsense_unused_rules`, so a run removes them.

### DMZ (`vtnet2`)

The segment that is exposed through Cloudflare, so it is the one most likely to
be compromised. It may talk to the internet and nothing else.

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 10 | Pass | 10.10.20.0/24 | 10.10.20.1 | UDP 53 | DNS on the gateway |
| 20 | **Block** | 10.10.20.0/24 | `HOME_LAN` | any | Isolation |
| 30 | **Block** | 10.10.20.0/24 | `LAB_NETS` | any | A compromised service cannot pivot into LAN or LAB |
| 40 | Pass | 10.10.20.0/24 | any | any | Internet - cloudflared dials out on 443 |

### LAB (`vtnet3`)

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 10 | Pass | 10.10.30.0/24 | 10.10.30.1 | UDP 53 | DNS on the gateway |
| 20 | **Block** | 10.10.30.0/24 | `HOME_LAN` | any | Isolation |
| 30 | **Block** | 10.10.30.0/24 | `LAB_NETS` | any | Isolated from LAN and DMZ too |
| 40 | Pass | 10.10.30.0/24 | any | any | Internet |

`LAB_NETS` contains the gateways themselves, so on DMZ and LAB sequence 30 also
drops ping to the gateway; only DNS (sequence 10) is let through to it.
Sequence 30 never sees traffic between two guests on the same segment — that
is switched inside the bridge. On the DMZ and LAB the host stops it instead:
the `network_bridge` role loads a bridge-family nftables table
(`guest_isolation`, from `/etc/network/guest-isolation.nft` via
`guest-isolation.service`) that lets a guest exchange frames with the
firewall's port only (`gateway_port`: `tap100i2`, `tap100i3`). Two DMZ guests
cannot even ARP for each other. Proxmox's own SDN "isolate ports" is not used
because it would isolate the firewall's port as well. The LAN has no such rule;
LAN guests talk to each other directly.

### NAT

Leave outbound NAT on **Automatic**. Internal traffic bound for the internet
gets translated to `192.168.1.201`; home-network-to-guest traffic is routed,
not translated, and its replies ride the existing state. No port forwards are
needed anywhere — Cloudflare Tunnel is outbound-only.

### DNS and DHCP

Because the internal segments are blocked from `192.168.1.0/24`, they cannot
ask the home router directly. **Unbound** on the firewall answers them on port
53 and forwards every query to the home router (`192.168.1.1`), which the
firewall itself may reach. The firewall's own resolver list under **System →
Settings → General** is `192.168.1.1` as well, with *Allow DNS server list to
be overridden by DHCP/PPP on WAN* on. Switching to public resolvers would mean
changing both the forwarder (`opnsense_dns_forwarders`) and that page.

**Dnsmasq** does DHCP only: its DNS port is moved to 53053 so it cannot collide
with Unbound, and it listens on LAN and LAB - the two segments with a pool.

## The static route on the home router

Add one route:

| Field | Value |
|---|---|
| Destination | `10.10.0.0` |
| Netmask | `255.255.0.0` |
| Gateway | `192.168.1.201` |

If the router cannot do static routes, put the route on your own machine
instead — that satisfies "I can reach the guests from my LAN" for you
personally, which is what was actually asked:

```bash
sudo ip route add 10.10.0.0/16 via 192.168.1.201
```

```powershell
route -p add 10.10.0.0 mask 255.255.0.0 192.168.1.201
```

`terraform output fallback_route_commands` prints the macOS variant too.

## Configuration as code

Everything the OPNsense API can write is declared in
`ansible/roles/opnsense_config/defaults/main.yml` and applied over the API;
what it can only report is declared there too, and checked:

| What | Where | How |
|---|---|---|
| Aliases `HOME_LAN`, `LAB_NETS` | `opnsense_aliases` | written |
| Every firewall rule in the tables above | `opnsense_rules` | written |
| Unbound forwarder | `opnsense_dns_forwarders` | written |
| Dnsmasq listen interfaces and DNS port | `opnsense_dnsmasq_interfaces`, `opnsense_dnsmasq_port` | written (partial settings update) |
| DHCP pools and reservations | `opnsense_segments`, `opnsense_dhcp_reservations` | written |
| Interface assignment, addresses, WAN block flags | `opnsense_baseline_interfaces` | checked |
| Gateway `WAN_GW` | `opnsense_baseline_gateways` | checked |
| Hostname, running sshd/unbound/dnsmasq | `opnsense_baseline_hostname`, `opnsense_baseline_services` | checked |

The rest of the console/GUI settings (time zone, DNS servers, SSH options) are
in the install steps above. The command lines are in
[commands.md](../commands.md); `--check --diff` is a real dry run - the checks
are reads, the modules compare without writing, and every `changed` in it is a
difference between the code and the firewall.

### The one-time credential

Create an API key once, in the GUI: **System → Access → Users → root → API
keys → +**. That downloads a file containing a key and a secret. Put both in
`.env`, under exactly these names - the role reads them with
`lookup('env', ...)`:

```
OPNSENSE_API_KEY=...
OPNSENSE_API_SECRET=...
```

Nothing loads `.env` by itself; the command in commands.md puts the two values
into the environment of that one run. Without them the role prints how to
create them and skips; it does not fail the converge.

### What protects a run

Not a savepoint: OPNsense 26.7 has no savepoint API any more (it went with the
os-firewall plugin), so a run that locks the firewall out does not roll itself
back. What there is instead:

- every run first reads back the interface, gateway and service baseline and
  stops before writing anything if it differs;
- `--check --diff` shows exactly what a run would change;
- a config backup taken beforehand (`GET /api/core/backup/download/this`, or
  System → Configuration → Backups) can be restored from the GUI or console.

The rules land in OPNsense's MVC filter, which is evaluated ahead of legacy
GUI rules (there are none). Rules not declared in the role are left alone
unless they are listed in `opnsense_unused_rules`.

---

## Traffic analysis

All under the OPNsense UI, and none of them is on (2026-10-03). The firewall
runs with 2 cores and 2048 MB; raise `memory` in
`terraform/modules/opnsense/variables.tf` to 8192 before turning all three on
at once.

- **Insight (NetFlow)** — built in. Enable under **Reporting → NetFlow**: pick
  WAN, LAN, DMZ and LAB as listening interfaces and `localhost` as the
  destination. Then **Reporting → Insight** gives per-host and per-port
  volumes over time. This is the "who is talking to whom" view.
- **Zenarmor** — the per-application dashboard, with a free Home edition.
  **System → Firmware → Plugins**, install `os-sunnyvalley` to add the vendor
  repository; Zenarmor then appears under **Services** and finishes its own
  install. Point it at the internal interfaces, not WAN, so it sees pre-NAT
  addresses and can attribute traffic to individual guests.
- **Suricata (IDS/IPS)** — built in, at **Services → Intrusion Detection**.
  Start in IDS (alert-only) mode on WAN with the ET Open ruleset before
  switching anything to IPS; a bad rule in IPS mode drops real traffic.

## Where Cloudflare fits

Each machine on the **DMZ** runs its services in Docker next to its own
`cloudflared`, which dials *out* to Cloudflare on 443. (The `10.10.20.10`
reservation is from an earlier single-container plan.) Nothing listens on your home IP, and the home
router forwards no ports — that is the whole point of choosing Tunnel over
public DNS plus port forwarding.

Consequences that are already baked into the rules above:

- The DMZ can reach the internet (sequence 40) so the tunnel can connect.
- The DMZ **cannot** initiate into LAN or LAB (sequence 30), so a
  compromised public service is contained.
- DMZ machines cannot reach each other either (the host's bridge rule), so a
  compromised machine cannot spread sideways. It is also why every machine
  needs its own tunnel: a `cloudflared` on one cannot proxy to a service on
  another.
- Services you publish should live on the DMZ, not the LAN. If something on the
  LAN must be published, put a reverse proxy in the DMZ and open exactly that
  one destination from DMZ to LAN, rather than relaxing sequence 30.

Adding **Cloudflare Access** in front of a hostname gives it an
authentication gate (Google/GitHub/e-mail OTP) without touching these rules.

No DMZ machine is built yet.

## Verifying it actually works

From a guest on the LAN:

```bash
ping -c1 10.10.10.1 && curl -s https://ifconfig.me && echo
```

Gateway answers, internet works. The LAN is trusted, so the home network and
the LAB answer too:

```bash
ping -c2 -W2 192.168.1.1; ping -c2 -W2 10.10.30.1
```

Then the part that matters, from a guest on the DMZ or LAB:

```bash
ping -c2 -W2 192.168.1.1; ping -c2 -W2 10.10.10.11
```

Both should **fail**. If either succeeds, sequence 20 or 30 on that interface
is missing or sits below an allow-any rule — order is evaluated top to bottom.

From your own machine on the home network:

```bash
ping -c1 10.10.10.11
```

Must succeed once the static route is in place.

## When the firewall is down

The guests lose all connectivity — that is by design. What you keep:

- `https://192.168.1.200:8006` — the Proxmox UI, on the home network
- The OPNsense console through that UI, including `pfctl -d` if you have locked
  yourself out of the web UI
- SSH to the Proxmox host. From there, `ip addr add 10.10.10.2/24 dev vmbr1`
  puts the host on the LAN segment temporarily, so the firewall's GUI and SSH
  answer on `10.10.10.1` even when its WAN side is locked; remove the address
  again with `ip addr del` afterwards

Nothing about recovering the firewall depends on the firewall.
