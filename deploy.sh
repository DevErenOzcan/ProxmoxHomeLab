#!/bin/bash

# Hata alındığında scripti durdur
set -e

# Terminal Renkleri
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Proxmox IaC Homelab Otomatik Dağıtım Aracı ===${NC}\n"

# Ön Gereksinim Kontrolü
command -v ansible-playbook >/dev/null 2>&1 || { echo -e "${RED}Hata: ansible yüklü değil.${NC}"; exit 1; }
command -v terraform >/dev/null 2>&1 || { echo -e "${RED}Hata: terraform yüklü değil.${NC}"; exit 1; }

# Proxmox parolasını alıp Terraform environment variable olarak set etme
echo -e "${YELLOW}Terraform Provider için Proxmox root parolasını girin (Gizli yazılır):${NC}"
read -s -p "Parola: " PROXMOX_PASSWORD
echo
export TF_VAR_proxmox_password="$PROXMOX_PASSWORD"

echo -e "\n${GREEN}[1/5] Ansible: Host Hazırlığı (01-host-prep.yml)...${NC}"
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/01-host-prep.yml

echo -e "\n${GREEN}[2/5] Ansible: GPU Passthrough (02-gpu-passthrough.yml)...${NC}"
ansible-playbook -i inventory/hosts.yml playbooks/02-gpu-passthrough.yml

echo -e "\n${GREEN}[3/5] Ansible: Vendor Reset Kurulumu (03-vendor-reset.yml)...${NC}"
ansible-playbook -i inventory/hosts.yml playbooks/03-vendor-reset.yml

# IOMMU ve VFIO parametrelerinin devreye girmesi için yeniden başlatma
echo -e "\n${YELLOW}[4/5] Sistem Yeniden Başlatılıyor...${NC}"
echo "GPU Passthrough ayarlarının geçerli olması için Proxmox host yeniden başlatılacak."
echo "Ansible sunucunun geri gelmesini otomatik olarak bekleyecek (Maksimum 10 dakika)..."

# Ansible reboot modülü sunucuyu yeniden başlatır ve SSH erişimi gelene kadar bekler
ansible -i inventory/hosts.yml proxmox_nodes -m reboot -a "reboot_timeout=600" --become
echo -e "${GREEN}Sunucu yeniden başlatıldı ve erişilebilir durumda.${NC}"
cd ..

echo -e "\n${GREEN}[5/5] Terraform: Sanal Makinelerin Kurulumu...${NC}"
cd terraform/environments/local

echo "Terraform Initialize ediliyor..."
terraform init -v

echo "Terraform Apply çalıştırılıyor..."
# -auto-approve flag'i ile onay beklemeden altyapıyı kurar
terraform apply -auto-approve

echo -e "\n${GREEN}=== Tüm işlemler başarıyla tamamlandı! ===${NC}"
echo "Ubuntu Server (192.168.3.10) ve Ubuntu Desktop (192.168.3.11) hazır."