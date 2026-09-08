#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Virtual Machine Provisioning (stage 2) ===${NC}\n"

WORK_DIR="./terraform/environments/local"

if [ ! -d "$WORK_DIR" ]; then
    echo -e "${YELLOW}Error: terraform directory not found. Run bootstrap.sh first.${NC}"
    exit 1
fi

cd "$WORK_DIR"

echo -e "${YELLOW}Enter the Proxmox root password for the Terraform provider (input is hidden):${NC}"
read -s -p "Password: " PROXMOX_PASSWORD
echo ""

# Terraform variables
export TF_VAR_proxmox_password="$PROXMOX_PASSWORD"
export TF_VAR_proxmox_endpoint="https://127.0.0.1:8006/"

echo -e "\n${GREEN}[1/2] Initializing Terraform...${NC}"
terraform init

echo -e "\n${GREEN}[2/2] Running terraform apply (creating the virtual machines)...${NC}"
terraform apply -auto-approve

echo -e "\n${GREEN}=== All virtual machines are up! ===${NC}"
