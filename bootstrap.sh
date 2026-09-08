#!/usr/bin/env bash
#
# Sets up the ANSIBLE STATE TREE on the Proxmox host. It does nothing else.
#
# This file used to fix repositories, edit GRUB, bind GPUs to vfio and reboot
# the host. All of that now lives in the roles under ansible/. The only job
# left here is: install ansible, put the state tree in place, and make it
# runnable.
#
# Usage (on the Proxmox host, as root):
#   ./bootstrap.sh              # install ansible + place state in /opt/proxmox-homelab
#   ./bootstrap.sh --apply      # ...and then run site.yml
#   ./bootstrap.sh --check      # ...and then do a dry run (--check --diff)
#
# From Windows, in one command:  ./sync.sh --bootstrap
#
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
say()  { printf "${GREEN}%s${NC}\n" "$*"; }
warn() { printf "${YELLOW}%s${NC}\n" "$*"; }
die()  { printf "${RED}ERROR: %s${NC}\n" "$*" >&2; exit 1; }

STATE_DIR="${STATE_DIR:-/opt/proxmox-homelab}"

# This script needs the ansible/ tree sitting next to it, so it cannot be
# piped in over stdin ('ssh host bash -s < bootstrap.sh'). Say so clearly
# instead of failing on an unbound BASH_SOURCE.
if [ -z "${BASH_SOURCE[0]:-}" ]; then
    die "Do not pipe this script into bash; it needs the ansible/ tree beside it. Copy the repo to the host first (sync.sh --bootstrap does it for you)."
fi
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="none"

for arg in "$@"; do
    case "$arg" in
        --apply) MODE="apply" ;;
        --check) MODE="check" ;;
        -h|--help) sed -n '2,18p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

say "=== Proxmox Ansible State Bootstrap ==="

# --- 1. Preconditions -------------------------------------------------------
[ "$(id -u)" -eq 0 ] || die "Must be run as root."
command -v pveversion >/dev/null 2>&1 || warn "pveversion not found - this may not be a Proxmox host."

# --- 2. Install ansible -----------------------------------------------------
# The enterprise repositories return 401, so 'apt update' may exit non-zero.
# That is fine: ansible comes from the Debian repository. Getting the
# repositories into their proper state is the pve_repos role's job, not
# bootstrap's.
if command -v ansible-playbook >/dev/null 2>&1; then
    say "[1/4] Ansible already installed: $(ansible-playbook --version | head -1)"
else
    warn "[1/4] Installing ansible..."
    apt-get update -y || warn "apt update partially failed (expected, enterprise repo) - continuing."
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        ansible-core python3-debian rsync \
        || die "Could not install ansible-core. Check the 'apt-get update' output."
    say "[1/4] Installed: $(ansible-playbook --version | head -1)"
fi

# --- 3. Place the state tree ------------------------------------------------
if [ "$SRC_DIR" != "$STATE_DIR" ]; then
    [ -f "$SRC_DIR/ansible/site.yml" ] || die "$SRC_DIR/ansible/site.yml not found. Run this from the repository root."
    warn "[2/4] Copying state into $STATE_DIR..."
    mkdir -p "$STATE_DIR"
    rsync -a --delete "$SRC_DIR/ansible/" "$STATE_DIR/ansible/"
    for extra in terraform run_vms.sh README.md; do
        if [ -e "$SRC_DIR/$extra" ]; then rsync -a "$SRC_DIR/$extra" "$STATE_DIR/"; fi
    done
else
    say "[2/4] State is already in $STATE_DIR."
fi
[ -f "$STATE_DIR/ansible/site.yml" ] || die "$STATE_DIR/ansible/site.yml not found."

# --- 4. The pve-state shortcut ----------------------------------------------
cat > /usr/local/bin/pve-state <<PVESTATE
#!/bin/sh
# Applies the proxmox-homelab state. All ansible-playbook arguments are passed through.
#   pve-state                 -> apply site.yml
#   pve-state --check --diff  -> dry run
#   pve-state --tags gpu      -> GPU passthrough only
cd "$STATE_DIR/ansible" || exit 1
exec ansible-playbook site.yml "\$@"
PVESTATE
chmod 0755 /usr/local/bin/pve-state
say "[3/4] Shortcut ready: pve-state"

# --- 5. Verify / optionally run ---------------------------------------------
cd "$STATE_DIR/ansible"
ansible-playbook site.yml --syntax-check >/dev/null || die "site.yml has a syntax error."
say "[4/4] site.yml syntax verified."

case "$MODE" in
    apply) warn "Applying site.yml..."; exec ansible-playbook site.yml ;;
    check) warn "Dry run (--check --diff)..."; exec ansible-playbook site.yml --check --diff ;;
esac

cat <<INFO

$(say "State ready: $STATE_DIR/ansible")

  Dry run      :  pve-state --check --diff
  Apply        :  pve-state
  Partial      :  pve-state --tags base|network|gpu|laptop
  Incl. reboot :  pve-state -e pve_reboot_after_converge=true

INFO
