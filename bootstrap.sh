#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Proxmox Host Hazırlık Scripti (1. Aşama) ===${NC}\n"

# --- 0. PROXMOX REPO DÜZELTMELERİ ---
echo -e "${YELLOW}[0/5] Proxmox Enterprise repoları devre dışı bırakılıyor...${NC}"

# enterprise.proxmox.com içeren .list ve .sources dosyalarını bul ve uzantılarını değiştirerek iptal et
for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    # Eğer dosya varsa ve içinde aradığımız metin geçiyorsa
    if [ -f "$file" ] && grep -q "enterprise.proxmox.com" "$file"; then
        mv "$file" "${file}.disabled"
        echo -e "${GREEN}Devre dışı bırakıldı: $file${NC}"
    fi
done

# No-Subscription reposunu ekle (Daha önce eklenmediyse)
if ! grep -rq "pve-no-subscription" /etc/apt/; then
    echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
    echo -e "${GREEN}No-Subscription reposu eklendi.${NC}"
fi

# 1. Paket Güncellemeleri
echo -e "${YELLOW}[1/5] Sistem güncelleniyor ve temel paketler kuruluyor...${NC}"
apt-get update -y
apt-get install -y git

# 2. Ansible Kurulumu
echo -e "${YELLOW}[2/5] Ansible kontrol ediliyor...${NC}"
if ! command -v ansible-playbook &> /dev/null; then
    apt-get install -y ansible
fi

# 3. Terraform Kurulumu (İkinci script için şimdiden kuruyoruz)
echo -e "${YELLOW}[3/5] Terraform kontrol ediliyor...${NC}"
if ! command -v terraform &> /dev/null; then
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update -y
    apt-get install -y terraform
fi

# 4. Repo İşlemleri
REPO_URL="https://github.com/DevErenOzcan/ProxmoxHomeLab.git"
WORK_DIR="/opt/proxmox-homelab"

echo -e "${YELLOW}[4/5] IaC Reposu ($WORK_DIR) alınıyor...${NC}"
if [ ! -d "$WORK_DIR" ]; then
    git clone "$REPO_URL" "$WORK_DIR"
else
    cd "$WORK_DIR" && git pull origin main
fi

cd "$WORK_DIR"

# 5. Router Dinamik MAC Ataması
echo -e "${YELLOW}[5/5] pfSense Router için dinamik WAN MAC adresi üretiliyor...${NC}"
DYNAMIC_MAC=$(printf '02:%02X:%02X:%02X:%02X:%02X\n' $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
MAIN_TF_PATH="terraform/environments/local/main.tf"

if [ -f "$MAIN_TF_PATH" ]; then
    sed -i -E "s/(wan_mac_address\s*=\s*\")[^\"]+(\")/\1$DYNAMIC_MAC\2/g" "$MAIN_TF_PATH"
    echo -e "${GREEN}Üretilen MAC Adresi: ${DYNAMIC_MAC}${NC}"
    echo -e "${YELLOW}DİKKAT: Modemde 192.168.1.200 IP'sini bu MAC adresine ($DYNAMIC_MAC) rezerve edin!${NC}"
fi

# 6. Ansible Operasyonları
echo -e "\n${GREEN}=== Ansible ile Host Konfigürasyonu Başlıyor ===${NC}"
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/01-host-prep.yml
ansible-playbook -i inventory/hosts.yml playbooks/02-gpu-passthrough.yml
ansible-playbook -i inventory/hosts.yml playbooks/03-vendor-reset.yml

# 7. REBOOT İŞLEMİ
echo -e "\n${RED}=== DİKKAT: GPU ayarlarının uygulanması için sistem şimdi YENİDEN BAŞLATILIYOR! ===${NC}"
echo "Sistem açıldıktan sonra sanal makineleri kurmak için 2. scripti çalıştırın."
sleep 5
reboot