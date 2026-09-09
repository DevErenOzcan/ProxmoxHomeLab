#!/usr/bin/env bash
#
# Runs Terraform against the local Proxmox node. Meant to be run ON the host
# (that is why the endpoint is 127.0.0.1), either directly or through
# `./sync.sh --shell`.
#
#   ./run_vms.sh                 plan, then ask before applying
#   ./run_vms.sh --guests        same, but also create the guest VMs
#   ./run_vms.sh --plan          plan only, change nothing
#   ./run_vms.sh --auto          apply without asking
#
# The first apply creates only the OPNsense ISO download and the firewall VM.
# Guests stay behind -var create_guests=true because a guest booted before the
# firewall exists has no gateway. See docs/network.md.
#
set -euo pipefail

GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'; NC=$'\033[0m'
say()  { printf '%s%s%s\n' "$GREEN"  "$*" "$NC"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; }
die()  { printf '%sERROR: %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$REPO_DIR/terraform/environments/local"

GUESTS=0
AUTO=0
PLAN_ONLY=0
for arg in "$@"; do
    case "$arg" in
        --guests) GUESTS=1 ;;
        --auto)   AUTO=1 ;;
        --plan)   PLAN_ONLY=1 ;;
        -h|--help) sed -n '3,15p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
        *) die "Unknown argument: $arg" ;;
    esac
done

[ -d "$WORK_DIR" ] || die "$WORK_DIR not found. Run this from the repository root."
command -v terraform >/dev/null 2>&1 || die "terraform is not installed. Run: pve-state --tags base"

# The bridges are host OS state managed by Ansible, not Terraform. Without them
# the firewall VM fails to start with "bridge 'vmbr2' does not exist".
for br in vmbr1 vmbr2 vmbr3; do
    ip link show "$br" >/dev/null 2>&1 || die "$br is missing. Run: pve-state --tags network"
done

cd "$WORK_DIR"

# Password resolution, in order: the environment, then .env, then a prompt.
# Note that sync.sh deliberately does NOT copy .env to the host -- the password
# has no business sitting in plaintext on the box it unlocks -- so on the host
# the .env branch never fires and you get the prompt. To run non-interactively
# there, pass it in:
#
#   TF_VAR_proxmox_password='...' ./run_vms.sh --auto
#
if [ -z "${TF_VAR_proxmox_password:-}" ]; then
    if [ -f "$REPO_DIR/.env" ] && grep -q '^proxmox_passwd=' "$REPO_DIR/.env"; then
        TF_VAR_proxmox_password="$(sed -n 's/^proxmox_passwd=//p' "$REPO_DIR/.env" | tr -d '\r\n')"
        say "Password read from .env"
    elif [ -t 0 ]; then
        read -r -s -p "Proxmox root password: " TF_VAR_proxmox_password
        echo
    else
        die "No terminal to prompt on. Set TF_VAR_proxmox_password, or run this from an interactive shell (./sync.sh --shell)."
    fi
fi
export TF_VAR_proxmox_password
export TF_VAR_proxmox_endpoint="${TF_VAR_proxmox_endpoint:-https://127.0.0.1:8006/}"

TF_ARGS=()
if [ "$GUESTS" -eq 1 ]; then
    TF_ARGS+=(-var "create_guests=true")
    warn "Guest VMs included."
else
    say "Firewall only. Add --guests once OPNsense is installed and routing."
fi

say "[1/3] terraform init"
terraform init -input=false

say "[2/3] terraform plan"
terraform plan -input=false "${TF_ARGS[@]}"

if [ "$PLAN_ONLY" -eq 1 ]; then
    say "Plan only, nothing applied."
    exit 0
fi

if [ "$AUTO" -ne 1 ]; then
    printf '%sApply this plan? [y/N] %s' "$YELLOW" "$NC"
    read -r reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) say "Cancelled."; exit 0 ;;
    esac
fi

say "[3/3] terraform apply"
terraform apply -input=false -auto-approve "${TF_ARGS[@]}"

echo
say "Done. What to do next:"
terraform output -json next_steps 2>/dev/null \
    | tr -d '[]"' | tr ',' '\n' | sed 's/^/  /' \
    || terraform output
