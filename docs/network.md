# Network design

Everything the guests do goes through an OPNsense firewall. This document is
the design: the topology, the address plan, the firewall policy and how to
verify it. Building it is in the bootstrap guides at the repo root
([opnsense-bootstrap.md](../opnsense-bootstrap.md) for the firewall).

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
          trusted guests      internet-facing     experiments,
                              services, each      quarantine
                              with cloudflared
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

Where that route lives is in [Reaching the segments from home](#reaching-the-segments-from-home).

## Address plan

| Segment | Bridge | Interface | Subnet | Gateway | Purpose |
|---|---|---|---|---|---|
| WAN | `vmbr0` | `vtnet0` | 192.168.1.0/24 | 192.168.1.1 | Faces the home network |
| LAN | `vmbr1` | `vtnet1` | 10.10.10.0/24 | 10.10.10.1 | Trusted guests |
| DMZ | `vmbr2` | `vtnet2` | 10.10.20.0/24 | 10.10.20.1 | Internet-facing services, each with its own cloudflared |
| LAB | `vmbr3` | `vtnet3` | 10.10.30.0/24 | 10.10.30.1 | Experiments, quarantine |

Fixed addresses:

| Address | Host |
|---|---|
| 192.168.1.200 | Proxmox host |
| 192.168.1.201 | OPNsense WAN |
| 10.10.10.11 | ubuntu-desktop (VM 102), DHCP reservation on `BC:24:11:B8:0E:F8` |
| 10.10.20.10 | dmz-docker (VM 110), static, set by cloud-init |

DHCP pools are `10.10.10.100-245` (LAN) and `10.10.30.100-199` (LAB) and are
for throwaway guests. The DMZ has no pool: its guests are cloud images whose
address cloud-init sets.

`terraform output` prints all of this, so you do not have to keep this table in
your head.

> Interface order matters. Proxmox maps `net0..net3` to FreeBSD
> `vtnet0..vtnet3` in order. Appending a NIC in
> `terraform/modules/opnsense/main.tf` is safe; **reordering** the
> `network_device` blocks silently rewires a running firewall.

## Building it

The order matters: the bridges are host state, and the desktop needs a gateway
that already exists.

1. The host and its bridges: [proxmox-bootstrap.md](../proxmox-bootstrap.md).
2. The firewall, installed with its WAN unplugged:
   [opnsense-bootstrap.md](../opnsense-bootstrap.md).
3. The desktop: [ubuntu-desktop-bootstrap.md](../ubuntu-desktop-bootstrap.md).
4. The DMZ Docker host: [dmz-docker-bootstrap.md](../dmz-docker-bootstrap.md).

## Firewall policy

The policy is asymmetric on purpose:

- **LAN is trusted.** Its machines reach everything, the home network
  included, and the home network reaches them: two-way.
- **DMZ and LAB reach the internet and nothing else.** Nothing there can open a
  connection into the LAN, the home network or each other's segment.
- **From home, only the LAN is reachable** - plus SSH from the workstation into
  the DMZ, which is how the DMZ machines are managed. LAB machines are reached
  through a LAN machine.

A stateful firewall needs only the initiating direction allowed; replies ride
the existing state.

These tables are the rules the firewall runs, one for one with
`opnsense_rules` in `ansible/roles/opnsense_config/defaults/main.yml`; `seq` is
the rule's sequence there. Traffic no rule matches falls to OPNsense's implicit
default block. Three aliases keep the rules readable:

| Alias | Type | Content |
|---|---|---|
| `HOME_LAN` | Network(s) | `192.168.1.0/24` |
| `LAB_NETS` | Network(s) | `10.10.0.0/16` |
| `MGMT_WORKSTATION` | Host(s) | `192.168.1.24`, the Windows workstation and its WSL |

`192.168.1.24` is a DHCP lease from the home router; reserve it there. If it
moves, WAN sequence 13 stops matching - the DMZ closes, it does not open.

### WAN (`vtnet0`)

**Block private networks** stays off on this interface — otherwise nothing
from `192.168.1.0/24` is ever evaluated and the rules below never match.

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 10 | Pass | `HOME_LAN` | this firewall | TCP 443 | Reach this web UI from home |
| 11 | Pass | `HOME_LAN` | 10.10.10.0/24 | any | Reach the LAN guests from home |
| 12 | Pass | `HOME_LAN` | this firewall | TCP 22 | SSH to the firewall from home |
| 13 | Pass | `MGMT_WORKSTATION` | 10.10.20.0/24 | TCP 22 | Manage the DMZ machines from the workstation |

Everything else inbound stays blocked by the implicit default: the rest of the
DMZ, and the whole LAB, which is reached through a LAN machine. Nothing from
the internet can reach in at all — the home router forwards no ports.

### LAN (`vtnet1`)

The trusted segment. Every machine on it may reach the home network, this
firewall, the DMZ, the LAB and the internet; traffic to the home network
leaves NATed as `192.168.1.201`. Together with WAN sequence 11 that makes
LAN ↔ home two-way. Nothing on the DMZ or LAB can open a connection into the
LAN — their own sequence 30 blocks `LAB_NETS`, which covers `10.10.10.0/24`.

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 50 | Pass | 10.10.10.0/24 | any | any (IPv4) | Everything; not logged |

One rule on purpose: it replaced the installer's default allow-all rules and
the per-path rules that sat unreachable under them. Nothing on the LAN uses
IPv6, so there is no IPv6 rule.

### DMZ (`vtnet2`)

The segment that is exposed through Cloudflare, so it is the one most likely to
be compromised. It may talk to the internet and nothing else.

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 10 | Pass | 10.10.20.0/24 | 10.10.20.1 | TCP/UDP 53 | DNS on the gateway; TCP for answers too big for UDP |
| 20 | **Block** | 10.10.20.0/24 | `HOME_LAN` | any | Isolation |
| 30 | **Block** | 10.10.20.0/24 | `LAB_NETS` | any | A compromised service cannot pivot into LAN or LAB |
| 40 | Pass | 10.10.20.0/24 | any | any | Internet - cloudflared dials out on 443 |

### LAB (`vtnet3`)

| seq | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 10 | Pass | 10.10.30.0/24 | 10.10.30.1 | TCP/UDP 53 | DNS on the gateway; TCP for answers too big for UDP |
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

## Reaching the segments from home

A machine on the home network reaches the LAN through the firewall's WAN
address, so it needs one route: `10.10.0.0/16` via `192.168.1.201`. The home
router (the ISP's ONT, with a restricted admin account) cannot hold a static
route, so the route lives on the machines that need it - today only the
Windows workstation that runs the controller:

```powershell
route -p add 10.10.0.0 mask 255.255.0.0 192.168.1.201
```

```bash
sudo ip route add 10.10.0.0/16 via 192.168.1.201      # Linux
```

`terraform output fallback_route_commands` prints the macOS variant too. A
router that can hold it needs the same route once: destination `10.10.0.0`,
netmask `255.255.0.0`, gateway `192.168.1.201`.

The other direction needs no route: LAN traffic to the home network leaves
NATed as `192.168.1.201`, so home devices can answer it as they are.

## Configuration as code

Everything the OPNsense API can write is declared in
`ansible/roles/opnsense_config/defaults/main.yml` and applied over the API;
what it can only report is declared there too, and checked:

| What | Where | How |
|---|---|---|
| Aliases `HOME_LAN`, `LAB_NETS`, `MGMT_WORKSTATION` | `opnsense_aliases` | written |
| Every firewall rule in the tables above | `opnsense_rules` | written |
| Unbound forwarder | `opnsense_dns_forwarders` | written |
| Dnsmasq listen interfaces and DNS port | `opnsense_dnsmasq_interfaces`, `opnsense_dnsmasq_port` | written (partial settings update) |
| DHCP pools and reservations | `opnsense_segments`, `opnsense_dhcp_reservations` | written |
| Interface assignment, addresses, WAN block flags | `opnsense_baseline_interfaces` | checked |
| Gateway `WAN_GW` | `opnsense_baseline_gateways` | checked |
| Hostname, running sshd/unbound/dnsmasq | `opnsense_baseline_hostname`, `opnsense_baseline_services` | checked |

The rest of the console/GUI settings (time zone, DNS servers, SSH options) and
the one-time API key are in [opnsense-bootstrap.md](../opnsense-bootstrap.md).
The command lines are in the README, "Day to day"; `--check --diff` is a real
dry run - the checks are reads, the modules compare without writing, and every
`changed` in it is a difference between the code and the firewall. Without the
API key in its environment the role prints how to create one and skips.

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
`cloudflared`, which dials *out* to Cloudflare on 443. Nothing listens on your
home IP, and the home router forwards no ports — that is the whole point of
choosing Tunnel over public DNS plus port forwarding.

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

The first DMZ machine is **dmz-docker** (VM 110, `10.10.20.10`,
[dmz-docker-bootstrap.md](../dmz-docker-bootstrap.md)). Its `cloudflared` and
its services share a Docker network, `edge`; the tunnel's public hostnames
point at containers by name, and no container publishes a port, so the only
thing listening on the VM's address is sshd for WAN sequence 13.

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

Must succeed once the static route is in place. From the workstation,
`ssh ubuntu@10.10.20.10 true` must succeed as well, and `ping -c1 10.10.20.10`
fail: sequence 13 lets SSH in and nothing else.

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
