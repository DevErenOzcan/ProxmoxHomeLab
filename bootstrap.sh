#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Proxmox Host Hazırlık Scripti ===${NC}\n"

# --- 0. PROXMOX REPO DÜZELTMELERİ ---
echo -e "${YELLOW}[1/10] Proxmox Enterprise repoları devre dışı bırakılıyor ve repo temizliği yapılıyor...${NC}"

# Çift kayıt (duplicate) uyarılarını önlemek için eski sources.list dosyasının içini boşaltıyoruz
> /etc/apt/sources.list

for file in /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; do
    if [ -f "$file" ] && grep -q "enterprise.proxmox.com" "$file"; then
        mv "$file" "${file}.disabled"
        echo -e "${GREEN}Devre dışı bırakıldı: $file${NC}"
    fi
done

if ! grep -rq "pve-no-subscription" /etc/apt/; then
    echo "deb http://download.proxmox.com/debian/pve trixie pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
    echo -e "${GREEN}No-Subscription reposu eklendi.${NC}"
fi

# --- 1. PAKET GÜNCELLEMELERİ VE GEREKSİNİMLER ---
echo -e "${YELLOW}[2/10] Sistem güncelleniyor ve temel paketler kuruluyor...${NC}"
apt-get update -y
apt-get dist-upgrade -y
apt-get install -y git dkms build-essential proxmox-headers-$(uname -r)

# --- 2. TERRAFORM KURULUMU ---
echo -e "${YELLOW}[3/10] Terraform kontrol ediliyor...${NC}"
if ! command -v terraform &> /dev/null; then
    wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
    # HashiCorp reposu doğrudan güncel 'trixie' sürümüyle eklendi
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com trixie main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update -y
    apt-get install -y terraform
    echo -e "${GREEN}Terraform kuruldu.${NC}"
else
    echo -e "${GREEN}Terraform zaten kurulu.${NC}"
fi

# --- 3. GRUB IOMMU AKTİVASYONU ---
echo -e "${YELLOW}[4/10] GRUB üzerinde IOMMU aktifleştiriliyor...${NC}"
sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt pcie_acs_override=downstream,multifunction"/' /etc/default/grub
update-grub

# --- 4. VFIO MODÜLLERİ ---
echo -e "${YELLOW}[5/10] VFIO modülleri ekleniyor...${NC}"
for mod in vfio vfio_iommu_type1 vfio_pci vfio_virqfd; do
    if ! grep -q "^$mod" /etc/modules; then
        echo "$mod" >> /etc/modules
    fi
done

# --- 5. GPU SÜRÜCÜLERİNİ KARALİSTEYE ALMA ---
echo -e "${YELLOW}[6/10] Host GPU sürücüleri karalisteye alınıyor...${NC}"
cat << 'EOF' > /etc/modprobe.d/pve-blacklist.conf
blacklist nouveau
blacklist radeon
blacklist amdgpu
EOF

# --- 6. GPU VFIO-PCI BIND ---
echo -e "${YELLOW}[7/10] GPU cihazları VFIO-PCI'a bağlanıyor...${NC}"
echo "options vfio-pci ids=10de:25a0,14c3:7961,1002:1637,1022:15df,1022:15e2,1022:15e3,1002:1638 disable_vga=1" > /etc/modprobe.d/vfio.conf

# --- 7. AMD VENDOR RESET YAMASI ---
echo -e "${YELLOW}[8/10] AMD Vendor Reset yaması kuruluyor...${NC}"
if ! dkms status | grep -q "vendor-reset"; then
    rm -rf /usr/src/vendor-reset
    git clone https://github.com/gnif/vendor-reset.git /usr/src/vendor-reset
    
    # Kernel uyumluluk yamaları (strlcpy -> strscpy ve unaligned.h header path)
    sed -i 's/strlcpy/strscpy/g' /usr/src/vendor-reset/src/amd/amdgpu/atom.c
    sed -i 's|<asm/unaligned.h>|<linux/unaligned.h>|g' /usr/src/vendor-reset/src/amd/amdgpu/atom.c
    
    cd /usr/src/vendor-reset
    dkms install . || echo -e "${RED}Vendor-reset kurulumunda hata oluştu veya zaten kurulu.${NC}"
    cd - > /dev/null
    
    echo "vendor-reset" > /etc/modules-load.d/vendor-reset.conf
    echo "options vendor-reset device_specific=1" > /etc/modprobe.d/vendor-reset.conf
    echo -e "${GREEN}Vendor reset kuruldu.${NC}"
else
    echo -e "${GREEN}Vendor reset zaten kurulu.${NC}"
fi

echo -e "${YELLOW}Initramfs güncelleniyor (bu işlem biraz sürebilir)...${NC}"
update-initramfs -u -k all

# --- 8. LAPTOP KAPAK (LID) AYARLARI ---
echo -e "${YELLOW}[9/10] Laptop kapak (lid) kapatma eylemleri devre dışı bırakılıyor...${NC}"
sed -i 's/.*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sed -i 's/.*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sed -i 's/.*HandleLidSwitchDocked=.*/HandleLidSwitchDocked=ignore/' /etc/systemd/logind.conf
echo -e "${GREEN}Kapak kapatma eylemleri 'ignore' olarak ayarlandı.${NC}"

# --- 9. REBOOT ---
echo -e "\n${RED}=== DİKKAT: GPU ayarlarının ve kernel modüllerinin uygulanması için sistem şimdi YENİDEN BAŞLATILIYOR! ===${NC}"
sleep 5
reboot
