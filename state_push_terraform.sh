#!/usr/bin/env bash
#
# Applies the TERRAFORM state to the Proxmox host, from here -- no need to log
# in to the host first.
#
# Terraform runs ON the host (its endpoint is loopback, so the API never leaves
# the box). This script mirrors the repository there, then drives terraform over
# SSH. The Proxmox password is read locally from .env and handed to the remote
# terraform on stdin, so it never lands on the host's disk or in its argv --
# .env itself is deliberately never copied over.
#
# USAGE
#   ./state_push_terraform.sh              Push, plan, ask, apply
#   ./state_push_terraform.sh --plan       Push and plan only, change nothing
#   ./state_push_terraform.sh --auto       Apply without asking
#   ./state_push_terraform.sh --no-guests  Firewall only, skip the guest VMs
#   ./state_push_terraform.sh --desktop    Also build the GPU-passthrough workstation
#   ./state_push_terraform.sh --output     Print the terraform outputs and stop
#   ./state_push_terraform.sh --destroy    Tear it all down (asks twice)
#   ./state_push_terraform.sh --init       Force terraform init -upgrade
#   ./state_push_terraform.sh --no-push    Use what is already on the host
#   ./state_push_terraform.sh --shell      Open a shell in the terraform directory
#
# Anything unrecognised is passed straight to terraform, e.g.
#   ./state_push_terraform.sh --plan -target=module.firewall
#
# Ansible has its own entry point: ./state_push_ansible.sh
#
# ORDER OF OPERATIONS
#   The bridges are host OS state owned by Ansible, and terraform itself is
#   installed by Ansible. So the first time round:
#       ./state_push_ansible.sh --tags base,network
#       ./state_push_terraform.sh
#   This script checks both and tells you which command is missing.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/push.sh
. "$REPO_DIR/lib/push.sh"

usage() { sed -n '3,36p' "${BASH_SOURCE[0]}" | sed 's/^#\{1,\} \{0,1\}//'; }

# --------------------------------------------------------------------------
# Arguments
# --------------------------------------------------------------------------
ACTION="apply"
AUTO=0
GUESTS=1        # cloud-image guests are created by default
DESKTOP=0       # the passthrough workstation is not (see vms.tf)
FORCE_INIT=0
DO_PUSH=1
PASSTHRU=()
while [ $# -gt 0 ]; do
    case "$1" in
        -p | --plan)    ACTION="plan" ;;
        -y | --auto)    AUTO=1 ;;
        -g | --guests)  GUESTS=1 ;;   # kept for muscle memory; now the default
        --no-guests)    GUESTS=0 ;;
        --desktop)      DESKTOP=1 ;;
        -o | --output)  ACTION="output" ;;
        --destroy)      ACTION="destroy" ;;
        --init)         FORCE_INIT=1 ;;
        --no-push)      DO_PUSH=0 ;;
        --shell)        ACTION="shell" ;;
        -h | --help)    usage; exit 0 ;;
        --)             shift; PASSTHRU+=("$@"); break ;;
        *)              PASSTHRU+=("$1") ;;
    esac
    shift
done

TF_VARS="-var create_guests=$([ "$GUESTS" -eq 1 ] && echo true || echo false)"
if [ "$DESKTOP" -eq 1 ]; then
    TF_VARS="$TF_VARS -var create_desktop=true"
fi

# --------------------------------------------------------------------------
# Remote terraform
# --------------------------------------------------------------------------
# Deliberately NOT using "terraform plan -out": a saved plan file records the
# values of all input variables, including the Proxmox password, and writing
# that to the host's disk is exactly what feeding the password over stdin
# avoids. The cost is that apply re-plans -- which is also a safety net, since
# it re-checks reality right before changing it.
tf_remote() {
    local tf_args="$1"
    # Always init. It is a second or so once the providers are cached, and it
    # is the only thing that notices a changed module source -- otherwise
    # editing a module path fails with "Module not installed" on the next plan.
    local init_cmd="terraform init -input=false"
    if [ "$FORCE_INIT" -eq 1 ]; then
        init_cmd="terraform init -input=false -upgrade"
    fi

    pssh_pw "set -e
cd '$TF_DIR'
export TF_VAR_proxmox_password=\"\$PW\"
export TF_VAR_proxmox_endpoint='$TF_ENDPOINT'
$init_cmd
terraform $tf_args"
}

extra_args() {
    if [ ${#PASSTHRU[@]} -gt 0 ]; then quote_args "${PASSTHRU[@]}"; fi
}

# --------------------------------------------------------------------------
# Main
# --------------------------------------------------------------------------
setup_auth

if [ "$ACTION" = "shell" ]; then
    open_shell "$TF_DIR"
fi

if [ "$DO_PUSH" -eq 1 ]; then
    push
fi

require_remote_terraform

case "$ACTION" in

    output)
        tf_remote "output$(extra_args)"
        ;;

    plan)
        info "terraform plan"
        tf_remote "plan -input=false $TF_VARS$(extra_args)"
        say "Plan only. Nothing was applied."
        ;;

    apply)
        if [ "$GUESTS" -eq 1 ]; then
            info "Firewall + cloud-image guests."
        else
            info "Firewall only (--no-guests)."
        fi
        if [ "$DESKTOP" -eq 1 ]; then
            warn "GPU-passthrough workstation included."
        fi

        if [ "$AUTO" -ne 1 ]; then
            info "terraform plan"
            tf_remote "plan -input=false $TF_VARS$(extra_args)"
            echo
            if ! confirm "Apply this plan? [y/N] "; then
                say "Cancelled."
                exit 0
            fi
        fi

        warn "terraform apply"
        tf_remote "apply -input=false -auto-approve $TF_VARS$(extra_args)"

        echo
        say "Applied. What to do next:"
        tf_remote "output -json next_steps" 2>/dev/null \
            | tr -d '[]"' | tr ',' '\n' | sed 's/^ */  /' \
            || true
        ;;

    destroy)
        warn "This destroys every guest Terraform manages on $PVE_HOST."
        info "terraform plan -destroy"
        tf_remote "plan -destroy -input=false $TF_VARS$(extra_args)"
        echo
        if ! confirm "Type 'destroy' to confirm: " "destroy"; then
            say "Cancelled."
            exit 0
        fi
        warn "terraform destroy"
        tf_remote "destroy -input=false -auto-approve $TF_VARS$(extra_args)"
        ;;
esac
