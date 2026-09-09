# shellcheck shell=bash
#
# Shared transport for the state_push_* entry points. Sourced, never executed.
#
# Both Ansible and Terraform are driven the same way: mirror the repository onto
# the Proxmox host over one SSH connection, then run the tool THERE. Nothing in
# this file assumes which of the two is being pushed.
#
# Provides:
#   say / warn / info / die      coloured output
#   setup_auth                   SSH key, else the password from .env
#   pssh <cmd>                   run a command on the host
#   pssh_pw <cmd>                same, with the password on the remote's stdin
#                                (the remote reads it into $PW)
#   push                         mirror the repository to $STATE_DIR
#   tree_signature               content hash of the mirrored dirs, for --watch
#   install_key                  set up key-based SSH
#   require_remote_terraform     preflight: terraform + bridges exist
#
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "lib/push.sh is a library; source it, do not run it." >&2
    exit 1
fi

# --------------------------------------------------------------------------
# Configuration -- every value can be overridden from the environment
# --------------------------------------------------------------------------
PVE_HOST="${PVE_HOST:-192.168.1.200}"
PVE_USER="${PVE_USER:-root}"
STATE_DIR="${STATE_DIR:-/opt/proxmox-homelab}"
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ENV_FILE="${ENV_FILE:-$REPO_DIR/.env}"
REMOTE_STAGE="/tmp/.proxmox-homelab-stage"

# Terraform lives on the host, so it talks to the API over loopback.
TF_DIR="${TF_DIR:-$STATE_DIR/terraform/environments/local}"
TF_ENDPOINT="${TF_ENDPOINT:-https://127.0.0.1:8006/}"

# Bridges Ansible creates and Terraform depends on. A guest attached to a
# missing bridge fails to start with "bridge 'vmbrN' does not exist".
REQUIRED_BRIDGES="${REQUIRED_BRIDGES:-vmbr1 vmbr2 vmbr3}"

# These are mirrored exactly (rsync --delete), so deleting a file locally also
# removes it on the host. Without that a removed .tf file lingers there and
# Terraform sees duplicate resources.
MIRROR_PATHS="${MIRROR_PATHS:-ansible terraform docs}"

# Copied but never deleted.
COPY_PATHS="${COPY_PATHS:-bootstrap.sh README.md}"

# Everything Terraform generates on the host. rsync does not delete excluded
# files (that would need --delete-excluded), so state, the provider lock file
# and tfvars survive every push.
STATE_EXCLUDES="--exclude=.terraform/ --exclude=.terraform.lock.hcl --exclude=*.tfstate --exclude=*.tfstate.* --exclude=*.tfvars --exclude=*.tfplan"

# --------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------
if [ -t 1 ]; then
    GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'
    BLUE=$'\033[0;36m';  NC=$'\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BLUE=''; NC=''
fi
say()  { printf '%s%s%s\n' "$GREEN"  "$*" "$NC"; }
warn() { printf '%s%s%s\n' "$YELLOW" "$*" "$NC"; }
info() { printf '%s%s%s\n' "$BLUE"   "$*" "$NC"; }
die()  { printf '%sERROR: %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }

# --------------------------------------------------------------------------
# Authentication
# --------------------------------------------------------------------------
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 -o LogLevel=ERROR)
ASKPASS_FILE=""
HOMELAB_PASSWORD=""

push_lib_cleanup() { if [ -n "$ASKPASS_FILE" ]; then rm -f "$ASKPASS_FILE"; fi; }
trap push_lib_cleanup EXIT

setup_auth() {
    if ssh "${SSH_OPTS[@]}" -o BatchMode=yes "$PVE_USER@$PVE_HOST" true 2>/dev/null; then
        info "Authentication: SSH key"
        return
    fi
    [ -f "$ENV_FILE" ] || die "$ENV_FILE is missing and SSH key auth does not work. Try --install-key."
    grep -q '^proxmox_passwd=' "$ENV_FILE" || die "$ENV_FILE has no 'proxmox_passwd=' line."

    # SSH has no TTY to prompt on here, so hand it an askpass helper instead.
    # The helper reads the password from .env at the moment ssh asks for it, so
    # the secret never lands in a second file, in argv, or in ps output.
    ASKPASS_FILE="$(mktemp)"
    {
        printf '%s\n' '#!/bin/sh'
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

pssh_tty() { ssh "${SSH_OPTS[@]}" -t "$PVE_USER@$PVE_HOST" "$@"; }

# The Proxmox API password, for tools that need it as a value rather than for
# the SSH login. .env is deliberately never copied to the host, so this is read
# locally and handed over per-command.
load_password() {
    [ -z "$HOMELAB_PASSWORD" ] || return 0
    if [ -n "${TF_VAR_proxmox_password:-}" ]; then
        HOMELAB_PASSWORD="$TF_VAR_proxmox_password"
    elif [ -f "$ENV_FILE" ] && grep -q '^proxmox_passwd=' "$ENV_FILE"; then
        HOMELAB_PASSWORD="$(sed -n 's/^proxmox_passwd=//p' "$ENV_FILE" | tr -d '\r\n')"
    elif [ -t 0 ]; then
        # read -p writes the prompt to stderr, so this is safe inside $( ).
        read -r -s -p "Proxmox root password: " HOMELAB_PASSWORD
        printf '\n' >&2
    else
        die "No password available. Put proxmox_passwd= in $ENV_FILE, or set TF_VAR_proxmox_password."
    fi
}

# Run a remote command with the password on its stdin. The remote script must
# start by consuming it, which is what the injected "read -r PW" does; the
# value is then in $PW. It never reaches the remote's argv or disk.
pssh_pw() {
    load_password
    printf '%s\n' "$HOMELAB_PASSWORD" | pssh "read -r PW
$1"
}

# --------------------------------------------------------------------------
# Push
# --------------------------------------------------------------------------
# The script that unpacks on the host. Unquoted heredoc on purpose: $VAR
# expands here and now, \$VAR is left for the remote shell.
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
for m in $MIRROR_PATHS; do
    if [ -d "$REMOTE_STAGE/\$m" ]; then
        mkdir -p "$STATE_DIR/\$m"
        rsync -a --delete $STATE_EXCLUDES "$REMOTE_STAGE/\$m/" "$STATE_DIR/\$m/"
    fi
done
for p in $COPY_PATHS; do
    if [ -e "$REMOTE_STAGE/\$p" ]; then rsync -a "$REMOTE_STAGE/\$p" $STATE_DIR/; fi
done
# Ownership from Windows is meaningless here, and ansible ignores ansible.cfg
# when the directory is not owned by the user running it.
chown -R root:root $STATE_DIR
if [ -f $STATE_DIR/bootstrap.sh ]; then chmod +x $STATE_DIR/bootstrap.sh; fi
rm -rf $REMOTE_STAGE
REMOTE_EOF
}

push() {
    local paths=()
    local p
    for p in $MIRROR_PATHS $COPY_PATHS; do
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

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
# Quote arguments that are passed straight through to the remote tool.
quote_args() {
    local out=""
    local a
    for a in "$@"; do
        out="$out $(printf '%q' "$a")"
    done
    printf '%s' "$out"
}

mirror_dirs() {
    local p
    for p in $MIRROR_PATHS; do
        if [ -d "$REPO_DIR/$p" ]; then printf '%s ' "$REPO_DIR/$p"; fi
    done
}

tree_signature() {
    # shellcheck disable=SC2046
    find $(mirror_dirs) -type f -print0 2>/dev/null \
        | sort -z | xargs -0 md5sum 2>/dev/null | md5sum | cut -d' ' -f1
}

install_key() {
    local key="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
    if [ ! -f "$key" ]; then
        warn "Generating an SSH key: $key"
        mkdir -p "$HOME/.ssh"
        chmod 700 "$HOME/.ssh"
        ssh-keygen -t ed25519 -N "" -C "proxmox-homelab" -f "$key"
    fi
    warn "Installing the public key on $PVE_USER@$PVE_HOST..."
    pssh 'mkdir -p /root/.ssh; chmod 700 /root/.ssh; touch /root/.ssh/authorized_keys; K=$(cat); if ! grep -qxF "$K" /root/.ssh/authorized_keys; then echo "$K" >> /root/.ssh/authorized_keys; fi' < "$key.pub"
    say "Key installed. Pushes run without a password from now on."
}

open_shell() {
    local dir="${1:-$STATE_DIR}"
    exec ssh "${SSH_OPTS[@]}" -t "$PVE_USER@$PVE_HOST" "cd $dir 2>/dev/null; exec bash -l"
}

# Terraform needs the host to be prepared by Ansible first.
require_remote_terraform() {
    pssh "set -e
if ! command -v terraform >/dev/null 2>&1; then
    echo 'terraform is not installed on the host. Run: ./state_push_ansible.sh --tags base' >&2
    exit 1
fi
for br in $REQUIRED_BRIDGES; do
    if ! ip link show \$br >/dev/null 2>&1; then
        echo \"bridge \$br is missing. Run: ./state_push_ansible.sh --tags network\" >&2
        exit 1
    fi
done
if [ ! -d $TF_DIR ]; then
    echo '$TF_DIR does not exist. Push first.' >&2
    exit 1
fi"
}

confirm() {
    local prompt="$1"
    local expected="${2:-y}"
    local reply
    if [ ! -t 0 ]; then
        die "Refusing to continue without confirmation and no terminal to ask on. Use --auto if you mean it."
    fi
    printf '%s%s%s' "$YELLOW" "$prompt" "$NC"
    read -r reply
    if [ "$expected" = "y" ]; then
        case "$reply" in y | Y | yes | YES) return 0 ;; *) return 1 ;; esac
    fi
    [ "$reply" = "$expected" ]
}
