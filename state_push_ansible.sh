#!/usr/bin/env bash
#
# Applies the ANSIBLE state to the Proxmox host, from here -- no need to log in
# to the host first.
#
# Ansible cannot act as a control node on Windows, so the model is not "run
# ansible against the host" but "push the state to the host and let ansible run
# there against itself". The transfer is one tar+ssh connection (no local rsync
# needed); the host side mirrors the tree with rsync --delete.
#
# USAGE
#   ./state_push_ansible.sh                  Push AND apply site.yml
#   ./state_push_ansible.sh --check          Push + dry run, change nothing
#   ./state_push_ansible.sh --push           Push only, run nothing
#   ./state_push_ansible.sh --tags gpu       Extra arguments go to ansible-playbook
#   ./state_push_ansible.sh --watch          Re-check automatically on every edit
#   ./state_push_ansible.sh --watch --run    ...and apply on every edit
#   ./state_push_ansible.sh --bootstrap      First-time setup (installs ansible)
#   ./state_push_ansible.sh --shell          Open a shell on the host
#   ./state_push_ansible.sh --install-key    Key-based SSH, so no password prompts
#
# Applying is the default. site.yml is idempotent, so a converge with nothing to
# do is a no-op -- but note that a change to GRUB, kernel modules or the
# initramfs reboots the host, because pve_reboot_after_converge defaults to
# true. To apply without that:
#
#   ./state_push_ansible.sh -e pve_reboot_after_converge=false
#
# Terraform has its own entry point: ./state_push_terraform.sh
#
# SETTINGS (environment variables)
#   PVE_HOST=192.168.1.200  PVE_USER=root  STATE_DIR=/opt/proxmox-homelab
#   WATCH_INTERVAL=2  PLAYBOOK=site.yml
#
# AUTHENTICATION
#   An SSH key is tried first. Without one, proxmox_passwd from .env is fed to
#   ssh through SSH_ASKPASS; the password never reaches argv or ps output.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/push.sh
. "$REPO_DIR/lib/push.sh"

WATCH_INTERVAL="${WATCH_INTERVAL:-2}"
PLAYBOOK="${PLAYBOOK:-site.yml}"

usage() { sed -n '3,38p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; }

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
WATCH=0
ACTION="run"   # applying is the default
ACTION_SET=0
PASSTHRU=()
while [ $# -gt 0 ]; do
    case "$1" in
        -w | --watch)               WATCH=1 ;;
        -r | --run)                 ACTION="run";       ACTION_SET=1 ;;
        -c | --check)               ACTION="check";     ACTION_SET=1 ;;
        -n | --push | --no-apply)   ACTION="push";      ACTION_SET=1 ;;
        -b | --bootstrap)           ACTION="bootstrap"; ACTION_SET=1 ;;
        --install-key)              ACTION="install-key"; ACTION_SET=1 ;;
        --shell)                    ACTION="shell";     ACTION_SET=1 ;;
        -h | --help)                usage; exit 0 ;;
        --)                         shift; PASSTHRU+=("$@"); break ;;
        *)                          PASSTHRU+=("$1") ;;
    esac
    shift
done

# Watching means "on every save". Inheriting the apply default there would
# converge - and possibly reboot the host - every time an editor writes a file.
# So watching alone dry-runs; ask for --run explicitly if that is what you want.
if [ "$WATCH" -eq 1 ] && [ "$ACTION_SET" -eq 0 ]; then
    ACTION="check"
fi

run_playbook() {
    local extra="$1"
    local args=""
    if [ ${#PASSTHRU[@]} -gt 0 ]; then args="$(quote_args "${PASSTHRU[@]}")"; fi
    pssh "cd $STATE_DIR/ansible && ansible-playbook $PLAYBOOK $extra$args"
}

do_action() {
    case "$ACTION" in
        push)
            info "Push only. Nothing was applied; add --run or drop --push."
            ;;
        check)
            info "Dry run (--check --diff)..."
            run_playbook "--check --diff"
            ;;
        run)
            warn "Applying $PLAYBOOK..."
            run_playbook ""
            ;;
        bootstrap)
            local args=""
            if [ ${#PASSTHRU[@]} -gt 0 ]; then args="$(quote_args "${PASSTHRU[@]}")"; fi
            warn "Running bootstrap.sh on the host..."
            pssh "bash $STATE_DIR/bootstrap.sh$args"
            ;;
    esac
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
setup_auth

case "$ACTION" in
    install-key) install_key; exit 0 ;;
    shell)       open_shell "$STATE_DIR/ansible" ;;
esac

if [ "$WATCH" -eq 1 ]; then
    say "Watching: $MIRROR_PATHS under $REPO_DIR  (Ctrl+C to stop)"
    if [ "$ACTION" = "check" ]; then
        info "Dry-running on every change. Use --watch --run to apply instead."
    fi
    last=""
    while true; do
        cur="$(tree_signature)"
        if [ "$cur" != "$last" ]; then
            push
            do_action || warn "The action failed; continuing to watch."
            last="$cur"
        fi
        sleep "$WATCH_INTERVAL"
    done
else
    push
    do_action
fi
