#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Sanal Makine Kurulum Scripti (2. Aşama) ===${NC}\n"

WORK_DIR="./terraform/environments/local"

if [ ! -d "$WORK_DIR" ]; then
    echo -e "${YELLOW}Hata: Terraform dizini bulunamadı. Lütfen önce bootstrap.sh scriptini çalıştırın.${NC}"
    exit 1
fi

cd "$WORK_DIR"

echo -e "${YELLOW}Terraform Provider için Proxmox root parolasını girin (Gizli yazılır):${NC}"
read -s -p "Parola: " PROXMOX_PASSWORD
echo ""

# Terraform Değişkenleri
export TF_VAR_proxmox_password="$PROXMOX_PASSWORD"
export TF_VAR_proxmox_endpoint="https://127.0.0.1:8006/"

echo -e "\n${GREEN}[1/2] Terraform Initialize ediliyor...${NC}"
terraform init

echo -e "\n${GREEN}[2/2] Terraform Apply çalışıyor (Sanal makineler kuruluyor)...${NC}"
terraform apply -auto-approve

echo -e "\n${GREEN}=== Tüm sanal makineler başarıyla ayağa kaldırıldı! ===${NC}"