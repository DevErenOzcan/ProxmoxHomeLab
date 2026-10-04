# DMZ Docker host bootstrap

The DMZ Docker host (VM 110, `dmz-docker`, 10.10.20.10) from nothing to
running containers published through its own Cloudflare Tunnel: the firewall
rule that lets the workstation in, the VM, the tunnel, and the playbook that
applies the rest. The last sections add a service and rebuild the VM.

The VM is Ubuntu Server 26.04 from Ubuntu's cloud image. cloud-init sets its
static address and the controller's SSH key on first boot; there is no
password, so the Proxmox console shows the boot but nobody can log in there.
SSH is the only way in, and only from the workstation (`192.168.1.24`) - WAN
sequence 13 on the firewall. Nothing on the VM listens for the internet:
`cloudflared` dials out to Cloudflare, and the services sit next to it on a
Docker network without published ports.

Its OS disk is disposable. Docker's whole state - images, containers, volumes
- and the compose projects live on a **50 GB persistent data disk** on the
host's `vmdata` storage, owned by a holder VM (`data-110`, VM 9110), so
destroying VM 110 leaves it in place.

Before you start:

- the host is converged, including the `vmdata` storage
  ([proxmox-bootstrap.md](proxmox-bootstrap.md));
- the firewall is running and configured ([opnsense-bootstrap.md](opnsense-bootstrap.md));
- the workstation keeps `192.168.1.24`. It is a DHCP lease: reserve it on the
  home router, or set it statically on Windows. If it moves, the firewall rule
  stops matching and the DMZ is unreachable until `MGMT_WORKSTATION` in
  `ansible/roles/opnsense_config/defaults/main.yml` follows it.

## 1. Let the workstation in

The rule and its alias are in the firewall role. Take a configuration backup
first (System → Configuration → Backups), then from `ansible/`, with the venv
active:

```bash
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml --check --diff
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml
```

The dry run should show exactly two changes: the `MGMT_WORKSTATION` alias and
WAN sequence 13, "Workstation may reach the DMZ over SSH".

## 2. Create the VM

Decide the data disk's size first: `data_disks` in
`terraform/environments/production/variables.tf` says 50 GB, reserved in full
on `vmdata`, and **it cannot be resized afterwards**. Then, from
`terraform/environments/production/`:

```bash
terraform plan -var-file=secret.tfvars
terraform apply -var-file=secret.tfvars
```

The plan adds three things and changes nothing else:

- the cloud image, which Proxmox downloads itself (about 825 MB, checked
  against `ubuntu_server_image_sha256`);
- the holder `data-110` with its disk. **Never start it**: two VMs running on
  one disk corrupt it. It carries Proxmox's protection flag;
- VM 110: 2 vCPUs, 3 GB of RAM, a 20 GB OS disk on `local-lvm`, the data disk
  as `scsi1`, `vmbr2`, and the cloud-init settings - `10.10.20.10/24` via
  `10.10.20.1`, DNS `10.10.20.1`, the controller's key for `ubuntu`
  (`ssh_public_keys`). It starts with the host.

The first boot takes a minute or two; the Proxmox console of VM 110 shows
cloud-init at work. Then, from the controller:

```bash
ssh ubuntu@10.10.20.10 true
```

To SSH from Windows itself rather than WSL, add Windows' own public key to
`ssh_public_keys` before the apply.

## 3. Create the tunnel

In the Cloudflare dashboard, under Zero Trust → Networks → Tunnels:

1. Create a tunnel of type **Cloudflared** and call it `dmz-docker`.
2. The install page shows a command with a long token after `--token`. Copy
   only the token, and do not run the command - Ansible runs `cloudflared`.
   Put the token in the repo's `.env`, under the name the playbook looks for:

   ```
   CLOUDFLARE_TUNNEL_TOKEN_DMZ_DOCKER=eyJh...
   ```

   The name is `CLOUDFLARE_TUNNEL_TOKEN_` plus the inventory name in capitals,
   `-` as `_`; every Docker host has its own tunnel and its own token.
3. Give the tunnel a public hostname (newer dashboards call it a published
   application route) for each service: Keycloak's is subdomain
   `auth-librenfra`, no path, service type **HTTP**, URL `keycloak:8080` - the
   compose service name and the port inside the container, never `localhost`,
   which is `cloudflared`'s own container. Cloudflare creates the DNS record
   itself. Keep subdomains **one level deep**: the free certificate covers
   `*.deverenozcan.com`, so `auth.librenfra.deverenozcan.com` fails the TLS
   handshake.

Keycloak's two passwords go into `.env` as well. Random ones, from the repo
root:

```bash
printf 'KEYCLOAK_DB_PASSWORD=%s\nKEYCLOAK_ADMIN_PASSWORD=%s\n' "$(openssl rand -hex 24)" "$(openssl rand -hex 24)" >> .env
```

`KEYCLOAK_ADMIN_PASSWORD` is the first login (user `admin`); see step 5.

None of these enters the repository; the playbook writes each to its
project's `.env` under `/mnt/data/compose/` on the VM, readable by root only.

## 4. Apply the configuration

From `ansible/`, with the venv active:

```bash
env $(grep -E '^(CLOUDFLARE_TUNNEL_TOKEN_|KEYCLOAK_)' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/docker_hosts/site.yml --check --diff
env $(grep -E '^(CLOUDFLARE_TUNNEL_TOKEN_|KEYCLOAK_)' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/docker_hosts/site.yml
```

On a VM without Docker the dry run stops checking after Docker's repository
and says so: nothing it would install exists yet. The real run:

1. **Formats the data disk only when it is completely blank**, as ext4
   labelled `docker-data`, and mounts it at `/mnt/data` (`--tags data`). A disk
   with anything else on it stops the run untouched.
2. Adds Docker's APT repository and writes `/etc/docker/daemon.json` before
   installing anything: `data-root` is `/mnt/data/docker`, so Docker's first
   start is already on the data disk, and the `local` log driver rotates
   container logs. A systemd drop-in keeps Docker from starting when the data
   disk is not mounted.
3. Installs Docker Engine and the compose plugin, and puts `ubuntu` in the
   `docker` group.
4. Copies each project in `docker_host_projects` from `ansible/compose/<name>/`
   to `/mnt/data/compose/<name>/`, writes its `.env`, and brings it up:
   `cloudflared` first, which creates the `edge` network, then `keycloak`
   (Keycloak and its PostgreSQL).

Everything it does is listed in
`ansible/inventories/production/group_vars/docker_hosts.yml`.

## 5. Check it

- The tunnel shows **HEALTHY** in the dashboard.
- `ssh ubuntu@10.10.20.10 docker ps` lists `cloudflared`, `keycloak` and
  `postgres`. Keycloak needs about a minute on its first start;
  `sudo docker logs -f keycloak-keycloak-1` says when it is listening.
- `https://auth-librenfra.deverenozcan.com` shows Keycloak's sign-in page. Sign
  in to the admin console as `admin` with `KEYCLOAK_ADMIN_PASSWORD`, create a
  permanent admin user in the `master` realm, sign in as that user and delete
  `admin`: Keycloak marks the bootstrap account as temporary.
- The DMZ is contained. On the VM, `curl -s https://ifconfig.me` works, while
  `ping -c2 -W2 192.168.1.1` and `ping -c2 -W2 10.10.10.11` fail
  ([docs/network.md](docs/network.md), "Verifying it actually works").

The admin console (`/admin`) is on the internet like the rest of Keycloak. A
Cloudflare Access application on `auth-librenfra.deverenozcan.com/admin` puts
a login in front of it at Cloudflare's edge, without affecting the sign-in
pages the applications use.

## Adding a service

1. Create `ansible/compose/<name>/compose.yaml`. Put the container that
   serves on the `edge` network (`external: true`) and publish no ports -
   `cloudflared` reaches it by name; anything behind it, like a database,
   stays on the project's own network. `ansible/compose/keycloak/compose.yaml`
   is the pattern.
2. Add `- name: <name>` to `docker_host_projects` in
   `group_vars/docker_hosts.yml`. A secret goes under the entry's `env:` as a
   `lookup('env', ...)` of a new variable in `.env`, like Keycloak's; the
   playbook refuses to run while it is empty. Add the variable's prefix to the
   `grep -E` in the command line.
3. Run the playbook again (`--tags docker` is enough).
4. Add a public hostname to the tunnel that points at `http://<container>:<port>`.

Removing an entry does not stop its containers. Take a project down by hand
first: `sudo docker compose -f /mnt/data/compose/<name>/compose.yaml down`,
then delete its directory.

Put **Cloudflare Access** in front of anything that is not meant for everyone:
it adds a login (Google, GitHub, e-mail code) at Cloudflare's edge, before a
request ever reaches the tunnel.

## Rebuilding the VM

When the OS is beyond repair, replace the VM - its data disk stays:

```bash
terraform apply -var-file=secret.tfvars -replace='module.dmz_docker.proxmox_virtual_environment_vm.server'
ssh-keygen -R 10.10.20.10
```

Proxmox destroys VM 110 and its own disks, but skips `vm-9110-disk-0`, which
belongs to `data-110`. The new VM boots the current cloud image with the same
address and key. Then repeat [step 4](#4-apply-the-configuration): the
playbook finds the `docker-data` filesystem, installs Docker with the same
`data-root`, and every container, image and volume is where it was.

The data disk is persistent, not backed up: it lives on one NVMe, and a failed
disk takes it along. Keep copies of what matters elsewhere.
