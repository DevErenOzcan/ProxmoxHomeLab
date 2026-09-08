#!/usr/bin/env bash
#
# Mirrors the local ansible state onto the Proxmox host over SSH.
#
# Ansible does not run on Windows, so the model is not "run ansible against the
# host" but "push the state to the host and let ansible run there".
# The transfer uses tar+ssh over a single connection (no local rsync required),
# and the host side mirrors it exactly with rsync --delete.
#
# USAGE
#   ./sync.sh                    Push only
#   ./sync.sh --check            Push + dry run (--check --diff)
#   ./sync.sh --run              Push + apply site.yml
#   ./sync.sh --run --tags gpu   Extra arguments are passed to ansible-playbook
#   ./sync.sh --watch --check    Push + dry run automatically on every change
#   ./sync.sh --bootstrap        Push + run bootstrap.sh on the host (first-time setup)
#   ./sync.sh --shell            Open a shell on the host
#   ./sync.sh --install-key      Set up key-based SSH so no password is needed
#
# SETTINGS (override with environment variables)
#   PVE_HOST=192.168.1.200  PVE_USER=root  STATE_DIR=/opt/proxmox-homelab
#
# AUTHENTICATION
#   An SSH key is tried first. Without one, the proxmox_passwd value from the
#   repository's .env is used via SSH_ASKPASS; the password never reaches the
#   command line or ps output.
#
set -euo pipefail

PVE_HOST="${PVE_HOST:-192.168.1.200}"
PVE_USER="${PVE_USER:-root}"
STATE_DIR="${STATE_DIR:-/opt/proxmox-homelab}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
REMOTE_STAGE="/tmp/.proxmox-homelab-stage"
WATCH_INTERVAL="${WATCH_INTERVAL:-2}"

# ansible/ is mirrored exactly (--delete). The other paths are only overwritten,
# so terraform state created on the host is never deleted.
MIRROR_PATH="ansible"
COPY_PATHS="terraform bootstrap.sh run_vms.sh README.md"

GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'
BLUE=$'\033[0;36m';  NC=$'\033[0m'
say()  { printf '%s%s%s\n' "$GREEN"  "$*" "$NC"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; }
info() { printf '%s%s%s\n' "$BLUE"   "$*" "$NC"; }
die()  { printf '%sERROR: %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }
usage() { sed -n '3,26p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; }

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
WATCH=0
ACTION="push"
PASSTHRU=()
while [ $# -gt 0 ]; do
    case "$1" in
        -w|--watch)     WATCH=1 ;;
        -r|--run)       ACTION="run" ;;
        -c|--check)     ACTION="check" ;;
        -b|--bootstrap) ACTION="bootstrap" ;;
        --install-key)  ACTION="install-key" ;;
        --shell)        ACTION="shell" ;;
        -h|--help)      usage; exit 0 ;;
        --)             shift; PASSTHRU+=("$@"); break ;;
        *)              PASSTHRU+=("$1") ;;
    esac
    shift
done

# --------------------------------------------------------------------------
# SSH authentication
# --------------------------------------------------------------------------
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR)
ASKPASS_FILE=""
cleanup() { if [ -n "$ASKPASS_FILE" ]; then rm -f "$ASKPASS_FILE"; fi; }
trap cleanup EXIT

setup_auth() {
    if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$PVE_USER@$PVE_HOST" true 2>/dev/null; then
        info "Authentication: SSH key"
        return
    fi
    [ -f "$ENV_FILE" ] || die "$ENV_FILE is missing and SSH key auth does not work. Try './sync.sh --install-key'."
    grep -q '^proxmox_passwd=' "$ENV_FILE" || die "$ENV_FILE has no 'proxmox_passwd=' line."

    ASKPASS_FILE="$(mktemp)"
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' '# Reads the password from its source; never copies it anywhere.'
        printf '%s\n' 'sed -n "s/^proxmox_passwd=//p" "$PVE_ENV_FILE" | tr -d "\r\n"'
    } > "$ASKPASS_FILE"
    chmod 700 "$ASKPASS_FILE"
    export PVE_ENV_FILE="$ENV_FILE"
    export SSH_ASKPASS="$ASKPASS_FILE"
    export SSH_ASKPASS_REQUIRE=force
    export DISPLAY="${DISPLAY:-:0}"
    SSH_OPTS+=(-o PreferredAuthentications=password -o PubkeyAuthentication=no)
    info "Authentication: password from .env"
}

pssh() { ssh "${SSH_OPTS[@]}" "$PVE_USER@$PVE_HOST" "$@"; }

# --------------------------------------------------------------------------
# Push
# --------------------------------------------------------------------------
# The unpack script that runs on the host. Unquoted heredoc: $VAR expands here,
# \$VAR is left for the remote shell.
remote_unpack_script() {
    cat <<REMOTE_EOF
set -e
rm -rf $REMOTE_STAGE
mkdir -p $REMOTE_STAGE
tar -xzf - --no-same-owner --no-same-permissions -C $REMOTE_STAGE

# Strip CRLF line endings coming from Windows. Otherwise shell scripts on the
# host fail with 'bad interpreter' and ansible writes CRLF into config files.
find $REMOTE_STAGE -type f \\( -name '*.yml' -o -name '*.yaml' -o -name '*.cfg' \\
     -o -name '*.j2' -o -name '*.sh' -o -name '*.md' -o -name '*.tf' \\) \\
     -exec sed -i 's/\\r\$//' {} +

mkdir -p $STATE_DIR
rsync -a --delete $REMOTE_STAGE/$MIRROR_PATH/ $STATE_DIR/$MIRROR_PATH/
for p in $COPY_PATHS; do
    if [ -e "$REMOTE_STAGE/\$p" ]; then rsync -a "$REMOTE_STAGE/\$p" $STATE_DIR/; fi
done
# Ownership from Windows is meaningless here, and ansible ignores ansible.cfg
# when the directory is not owned by the user running it.
chown -R root:root $STATE_DIR
if [ -f $STATE_DIR/bootstrap.sh ]; then chmod +x $STATE_DIR/bootstrap.sh; fi
if [ -f $STATE_DIR/run_vms.sh ]; then chmod +x $STATE_DIR/run_vms.sh; fi
rm -rf $REMOTE_STAGE
REMOTE_EOF
}

push() {
    local paths=()
    local p
    for p in $MIRROR_PATH $COPY_PATHS; do
        if [ -e "$REPO_DIR/$p" ]; then paths+=("$p"); fi
    done
    [ ${#paths[@]} -gt 0 ] || die "Nothing to push."

    tar -C "$REPO_DIR" -czf - \
        --exclude=.git --exclude=.env --exclude=.idea \
        --exclude=.terraform --exclude='*.tfstate' --exclude='*.tfstate.backup' \
        --exclude='*.retry' --exclude=__pycache__ \
        "${paths[@]}" \
    | pssh "$(remote_unpack_script)"
    say "-> $PVE_USER@$PVE_HOST:$STATE_DIR updated ($(date +%H:%M:%S))"
}

run_playbook() {
    local extra="$1"
    local args=""
    local a
    if [ ${#PASSTHRU[@]} -gt 0 ]; then
        for a in "${PASSTHRU[@]}"; do
            args="$args $(printf '%q' "$a")"
        done
    fi
    pssh "cd $STATE_DIR/ansible && ansible-playbook site.yml $extra$args"
}

tree_signature() {
    find "$REPO_DIR/$MIRROR_PATH" -type f -print0 2>/dev/null \
        | sort -z | xargs -0 md5sum 2>/dev/null | md5sum | cut -d' ' -f1
}

install_key() {
    local key="$HOME/.ssh/id_ed25519"
    if [ ! -f "$key" ]; then
        warn "Generating an SSH key: $key"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -C "proxmox-homelab" -f "$key"
    fi
    warn "Installing the public key on $PVE_USER@$PVE_HOST..."
    cat "$key.pub" | pssh 'mkdir -p /root/.ssh; chmod 700 /root/.ssh; touch /root/.ssh/authorized_keys; K=$(cat); if ! grep -qxF "$K" /root/.ssh/authorized_keys; then echo "$K" >> /root/.ssh/authorized_keys; fi'
    say "Key installed. From now on sync runs without a password."
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
setup_auth

case "$ACTION" in
    install-key)
        install_key
        exit 0
        ;;
    shell)
        exec ssh "${SSH_OPTS[@]}" -t "$PVE_USER@$PVE_HOST" "cd $STATE_DIR/ansible 2>/dev/null; exec bash -l"
        ;;
esac

do_action() {
    case "$ACTION" in
        push)      : ;;
        check)     info "Dry run (--check --diff)..."; run_playbook "--check --diff" ;;
        run)       warn "Applying site.yml..."; run_playbook "" ;;
        bootstrap) warn "Running bootstrap.sh..."; pssh "bash $STATE_DIR/bootstrap.sh" ;;
    esac
}

if [ "$WATCH" -eq 1 ]; then
    say "Watching: $REPO_DIR/$MIRROR_PATH  (Ctrl+C to stop)"
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
