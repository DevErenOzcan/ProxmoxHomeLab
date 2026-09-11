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
| 10.10.20.10 | cloudflared container |
| 10.10.10.10 | ubuntu-server |
| 10.10.10.11 | ubuntu-desktop |
| 10.10.10.12 | windows-11-desktop |

DHCP pools start at `.100` in each segment and are for throwaway guests.

`terraform output` prints all of this, so you do not have to keep this table in
your head.

> Interface order matters. Proxmox maps `net0..net3` to FreeBSD
> `vtnet0..vtnet3` in order. Appending a NIC in
> `terraform/modules/opnsense/main.tf` is safe; **reordering** the
> `network_device` blocks silently rewires a running firewall.

## Order of operations

Both steps run from your own machine; neither needs a login on the host.

**1. Create the bridges** — host OS state, so this is Ansible's job:

```bash
./state_push_ansible.sh --tags network
```

**2. Create the firewall VM:**

```bash
./state_push_terraform.sh
```

This creates only the OPNsense ISO download and the firewall VM. The guest VMs
are gated behind `create_guests`, which defaults to `false`, because a guest
booted before the firewall exists has no gateway.

**3. Install and configure OPNsense** — the sections below. This part is
manual: OPNsense has no unattended installer.

**4. Add the static route** on the home router.

**5. Create the guests:**

```bash
./state_push_terraform.sh --guests
```

## Installing OPNsense

> **The WAN interface starts unplugged, and it has to.** A fresh OPNsense
> applies a factory config of `LAN = 192.168.1.1/24` with a DHCP server on it.
> This home network already uses 192.168.1.0/24, so the moment that config
> touches `vmbr0` the VM starts answering ARP for the real router's address and
> serving its own leases — the whole house loses internet, not just the lab.
> That is not hypothetical; it happened here on 2026-09-09 and took the host's
> own DNS down with it.
>
> `firewall_wan_connected` therefore defaults to `false`, which sets
> `disconnected` on net0. Install and assign interfaces first, then connect it.

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
   `192.168.1.1`; say no to DHCP on every interface for now; say no to IPv6.

4. Only now plug WAN in:

   ```bash
   ./state_push_terraform.sh -var firewall_wan_connected=true
   ```

   Set it in a `.tfvars` file instead if you would rather not repeat the flag.
   Until this runs, the firewall can see its internal segments but not the home
   network — which is exactly what you want while it still thinks it is
   192.168.1.1.

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

First create two aliases under **Firewall → Aliases** so the rules stay
readable:

| Alias | Type | Content |
|---|---|---|
| `HOME_LAN` | Network(s) | `192.168.1.0/24` |
| `LAB_NETS` | Network(s) | `10.10.0.0/16` |

### WAN (`vtnet0`)

Under **Interfaces → WAN**, uncheck **Block private networks** — otherwise
nothing from `192.168.1.0/24` is ever evaluated and the rules below never
match.

| # | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 1 | Pass | `HOME_LAN` | WAN address | 443 | Reach this web UI from home |
| 2 | Pass | `HOME_LAN` | `LAB_NETS` | any | Reach the guests from home |

Everything else inbound stays blocked by the implicit default. Nothing from the
internet can reach in at all — the home router forwards no ports.

### LAN (`vtnet1`) — order matters

| # | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 1 | Pass | LAN net | LAN address | 53, ICMP | DNS and ping to the gateway |
| 2 | **Block** | LAN net | `HOME_LAN` | any | **The isolation requirement** |
| 3 | Block | LAN net | 10.10.30.0/24 | any | Keep the lab out of reach |
| 4 | Pass | LAN net | 10.10.20.0/24 | any | LAN may use DMZ services |
| 5 | Pass | LAN net | any | any | Internet |

### DMZ (`vtnet2`)

The segment that is exposed through Cloudflare, so it is the one most likely to
be compromised. It may talk to the internet and nothing else.

| # | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 1 | Pass | DMZ net | DMZ address | 53, ICMP | DNS and ping to the gateway |
| 2 | **Block** | DMZ net | `HOME_LAN` | any | Isolation |
| 3 | **Block** | DMZ net | 10.10.10.0/24 | any | A compromised service cannot pivot into LAN |
| 4 | Block | DMZ net | 10.10.30.0/24 | any | Nor into the lab |
| 5 | Pass | DMZ net | any | 443, 53 | cloudflared's outbound tunnel |

### LAB (`vtnet3`)

| # | Action | Source | Destination | Port | Why |
|---|---|---|---|---|---|
| 1 | Pass | LAB net | LAB address | 53, ICMP | DNS and ping to the gateway |
| 2 | **Block** | LAB net | `HOME_LAN` | any | Isolation |
| 3 | **Block** | LAB net | `LAB_NETS` | any | Isolated from LAN and DMZ too |
| 4 | Pass | LAB net | any | any | Internet |

Rule 3 does not affect traffic between two guests on the same segment — that
never reaches the firewall, it is switched inside the bridge. If you need
guest-to-guest isolation inside one segment, that is the Proxmox per-VM
firewall, not OPNsense.

### NAT

Leave outbound NAT on **Automatic**. Internal traffic bound for the internet
gets translated to `192.168.1.201`; home-network-to-guest traffic is routed,
not translated, and its replies ride the existing state. No port forwards are
needed anywhere — Cloudflare Tunnel is outbound-only.

### DNS

Because the internal segments are blocked from `192.168.1.0/24`, they cannot
use the home router as a resolver. Run **Unbound** on OPNsense (Services →
Unbound DNS), listening on LAN/DMZ/LAB, and set the upstream resolvers under
**System → Settings → General** to something public (`1.1.1.1`, `9.9.9.9`).
Leave *Allow DNS server list to be overridden by DHCP/PPP on WAN* unchecked, or
the home router's resolver comes back in through the side door.

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

Interface assignment and addressing are the only parts that stay manual — the
OPNsense API does not expose them. Everything else is declared in
`ansible/roles/opnsense_config/defaults/main.yml` and applied over the API:

| What | Where |
|---|---|
| Aliases `HOME_LAN`, `LAB_NETS` | `opnsense_aliases` |
| Every firewall rule in the tables above | `opnsense_rules` |
| Unbound forwarders | `opnsense_dns_forwarders` |
| DHCP pools and reservations | `opnsense_segments`, `opnsense_dhcp_reservations` |

```bash
./state_push_ansible.sh --tags firewall
```

### The one-time credential

Create an API key once, in the GUI: **System → Access → Users → root → API
keys → +**. That downloads a file containing a key and a secret. Put both in
`.env`:

```
opnsense_api_key=...
opnsense_api_secret=...
```

`state_push_ansible.sh` forwards them to the host on stdin as environment
variables, so they never reach the host's disk or its argv — the same
treatment the Proxmox password gets. Without them the role prints how to
create them and skips; it does not fail the converge.

### Why this is safe to run remotely

The role wraps its changes in an OPNsense **savepoint**. If a rule locks the
firewall out of its own management network, OPNsense rolls the configuration
back on its own when the savepoint is not confirmed in time. The role confirms
it only after every change has applied, and reverts explicitly if any step
fails, so a half-applied ruleset is not a state you can end up in.

The rules land in the `os-firewall` plugin's *Automation* ruleset, which is
evaluated ahead of anything created in the GUI. Rules you added by hand are
left alone.

---

## Traffic analysis

All under the OPNsense UI. Sized for `firewall_memory = 4096`; raise it to
`8192` in `terraform.tfvars` before turning all three on at once.

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

`cloudflared` runs in a container on the **DMZ** at `10.10.20.10` and dials
*out* to Cloudflare on 443. Nothing listens on your home IP, and the home
router forwards no ports — that is the whole point of choosing Tunnel over
public DNS plus port forwarding.

Consequences that are already baked into the rules above:

- The DMZ can reach the internet (rule 5) so the tunnel can connect.
- The DMZ **cannot** initiate into LAN or LAB (rules 3 and 4), so a
  compromised public service is contained.
- Services you publish should live on the DMZ, not the LAN. If something on the
  LAN must be published, put a reverse proxy in the DMZ and open exactly that
  one destination from DMZ to LAN, rather than relaxing rule 3.

Adding **Cloudflare Access** in front of a hostname gives it an
authentication gate (Google/GitHub/e-mail OTP) without touching these rules.

The container itself is not built yet — that is the next step after the
firewall is up and routing.

## Verifying it actually works

From a guest on the LAN:

```bash
ping -c1 10.10.10.1 && curl -s https://ifconfig.me && echo
```

Gateway answers, internet works. Then the part that matters:

```bash
ping -c2 -W2 192.168.1.1; ping -c2 -W2 192.168.1.200
```

Both must **fail**. If either succeeds, rule 2 on that interface is missing or
sits below the allow-any rule — order is evaluated top to bottom.

From your own machine on the home network:

```bash
ping -c1 10.10.10.10
```

Must succeed once the static route is in place.

## When the firewall is down

The guests lose all connectivity — that is by design. What you keep:

- `https://192.168.1.200:8006` — the Proxmox UI, on the home network
- The OPNsense console through that UI, including `pfctl -d` if you have locked
  yourself out of the web UI
- SSH to the Proxmox host, and `./state_push_ansible.sh --shell` from this repo

Nothing about recovering the firewall depends on the firewall.
