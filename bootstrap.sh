#!/bin/bash
# Hata aldığında scripti durdur
set -e

# Terminal Renkleri
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Proxmox IaC Homelab Otomatik Kurulum (Bootstrap) ===${NC}\n"

# --- 1. SİSTEM GÜNCELLEMESİ VE TEMEL PAKETLER ---
echo -e "${YELLOW}[1/4] Sistem güncelleniyor ve temel paketler kuruluyor...${NC}"
apt-get update -y
apt-get install -y git curl wget unzip software-properties-common gnupg2

# --- 2. ANSIBLE KURULUMU ---
echo -e "${YELLOW}[2/4] Ansible kuruluyor...${NC}"
if ! command -v ansible-playbook &> /dev/null; then
    apt-get install -y ansible
    echo -e "${GREEN}Ansible başarıyla kuruldu.${NC}"
else
    echo -e "${GREEN}Ansible zaten kurulu, geçiliyor.${NC}"
fi

# --- 3. TERRAFORM KURULUMU ---
echo -e "${YELLOW}[3/4] Terraform kuruluyor...${NC}"
if ! command -v terraform &> /dev/null; then
    # HashiCorp GPG anahtarını ekle
    wget -O- https://apt.releases.hashicorp.com/gpg | \
        gpg --dearmor | \
        tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    
    # HashiCorp reposunu ekle
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] \
        https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
        tee /etc/apt/sources.list.d/hashicorp.list
    
    apt-get update -y
    apt-get install -y terraform
    echo -e "${GREEN}Terraform başarıyla kuruldu.${NC}"
else
    echo -e "${GREEN}Terraform zaten kurulu, geçiliyor.${NC}"
fi

# --- 4. REPOYU ÇEKME (VEYA GÜNCELLEME) ---
REPO_URL="https://github.com/SENIN_KULLANICI_ADIN/SENIN_REPO_ADIN.git" # BURAYI KENDİ REPO URL'N İLE DEĞİŞTİR!
WORK_DIR="/opt/proxmox-homelab"

echo -e "${YELLOW}[4/4] IaC Reposu ($REPO_URL) alınıyor...${NC}"

if [ ! -d "$WORK_DIR" ]; then
    git clone "$REPO_URL" "$WORK_DIR"
else
    echo -e "${YELLOW}Repo dizini zaten var, güncellemeler çekiliyor...${NC}"
    cd "$WORK_DIR"
    git pull origin main # veya master, branch adın neyse
fi

cd "$WORK_DIR"

# Proxmox parolasını Terraform environment variable olarak set etme
echo -e "${YELLOW}Terraform Provider için Proxmox root parolasını girin (Gizli yazılır):${NC}"
read -s -p "Parola: " PROXMOX_PASSWORD
echo ""
export TF_VAR_proxmox_password="$PROXMOX_PASSWORD"

# --- BUNDAN SONRASI SENİN ORİJİNAL İŞLEMLERİN ---

# Localhost'a bağlanabilmesi için ufak bir Ansible ayarı gerekebilir, 
# eğer inventory dosyan 192.168.1.200 (kendi IP'si) gösteriyorsa sorun yok.
# Ancak bu scripti doğrudan Proxmox üzerinde çalıştırdığımız için,
# Ansible'ın ssh key sormadan kendine (veya ilgili IP'ye) bağlanabilmesi önemli.

echo -e "\n${GREEN}[Operasyon 1/4] Ansible: Host Hazırlığı (01-host-prep.yml)...${NC}"
# -c local parametresi eklenebilir eğer inventory yerine localhost üzerinden gidilecekse,
# ama senin inventory'n varsa onu kullanalım. Şifre sormaması için SSH ayarı yapılması gerekebilir.
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/01-host-prep.yml

echo -e "\n${GREEN}[Operasyon 2/4] Ansible: GPU Passthrough (02-gpu-passthrough.yml)...${NC}"
ansible-playbook -i inventory/hosts.yml playbooks/02-gpu-passthrough.yml

echo -e "\n${GREEN}[Operasyon 3/4] Ansible: Vendor Reset Kurulumu (03-vendor-reset.yml)...${NC}"
ansible-playbook -i inventory/hosts.yml playbooks/03-vendor-reset.yml

# IOMMU ve VFIO parametrelerinin devreye girmesi için yeniden başlatma
echo -e "\n${YELLOW}[Operasyon 4/4] Sistem Yeniden Başlıyor...${NC}"
echo "GPU Passthrough ayarlarının geçerli olması için Proxmox host yeniden başlatılacak."
echo "DİKKAT: Sistem yeniden başladıktan sonra Terraform kurulumunu manuel tetiklemeniz gerekebilir,"
echo "çünkü makine kapanınca bu script duracaktır."
echo "Otomatik devam etmesi için bir systemd servisi yazılması gerekir."

# Yeniden başlatma komutu (Şimdilik yoruma aldım, otomatik başlatmasın diye)
# reboot

# EĞER YENİDEN BAŞLATMA GEREKMİYORSA VEYA SONRA YAPACAKSAN:
echo -e "\n${GREEN}=== Terraform: Sanal Makinelerin Kurulumu ===${NC}"
cd ../terraform/environments/local
echo "Terraform Initialize ediliyor..."
terraform init -v
echo "Terraform Apply çalışıyor..."
terraform apply -auto-approve

echo -e "\n${GREEN}=== Tüm işlemler başarıyla tamamlandı! ===${NC}"