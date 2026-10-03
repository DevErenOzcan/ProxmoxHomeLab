# Proxmox HomeLab Commands

Yönetim ve kurulum komutları tamamen standart CLI araçlarına dayanır.
Aşağıdaki komutları doğrudan terminalinizden kopyalayıp çalıştırabilirsiniz.

## Adım 0: Controller ortamı (tek seferlik)

Ansible sistem geneline kurulmaz: repo kendi controller ortamını repo kökündeki
`.venv` içinde taşır. WSL/Linux içinden, repo kökünde:

```bash
python3 -m venv .venv
.venv/bin/pip install -r ansible/requirements.txt
.venv/bin/ansible-galaxy collection install -r ansible/requirements.yml
```

Windows'tan oluşturulan bir venv (`Scripts/python.exe`) burada işe yaramaz;
ansible'ın Windows control node'u yok. Son iki komut idempotenttir, iki
requirements dosyasından biri değiştiğinde tekrar çalıştırın.

Sonrasında ortamı etkinleştirin — `ansible-playbook` artık venv'inkidir:

```bash
. .venv/bin/activate
```

*(Etkinleştirmek istemezseniz komutlarda `ansible-playbook` yerine
`../.venv/bin/ansible-playbook` yazın. Çıplak `ansible-playbook`, venv dışında
apt'ın `/usr/bin/ansible-playbook`'una düşer; o da `/usr/bin/python3`'ten
import ettiği için `.venv`'deki httpx'i göremez ve firewall rolü patlar.)*

`.env.example` dosyasını `.env` olarak kopyalayıp OPNsense API anahtarlarını
yazın. Bu dosya kendiliğinden yüklenmez; Adım 3'teki komut onu o koşuya taşır.

## `ANSIBLE_CONFIG` neden her komutta var

`/mnt/c` world-writable olduğu için ansible oradaki `ansible.cfg`'yi **sessizce
yok sayar** — envanter, `roles_path` (her rol "not found") ve pipelining devre
dışı kalır. Dosyayı açıkça göstermek bu kontrolü atlar. Kalıcı çözüm, `/mnt/c`
mount'unu world-writable olmaktan çıkarmaktır: `/etc/wsl.conf` içine
`[automount]` altında `options = "metadata,umask=22,fmask=111"` ekleyip
`wsl --shutdown`. Bunu yaparsanız `ANSIBLE_CONFIG=` önekini bırakabilirsiniz.

## Adım 1: Proxmox Host Konfigürasyonu
Proxmox sunucusunun temel ayarlarını, depolarını, ağ köprülerini (bridge) ve
GPU Passthrough ayarlarını yapmak için:

```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/proxmox/site.yml
```

Önce kuru çalıştırma, hiçbir şeyi değiştirmez:

```bash
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/proxmox/site.yml --check --diff
```

Yeniden başlatma ihtimali olmayan güvenli alt küme (depolar, paketler,
terraform): aynı komuta `--tags base` ekleyin.

*(`-i` vermeye gerek yok: `ansible.cfg` zaten `inventories/production`'ı
gösteriyor ve `ANSIBLE_CONFIG` sayesinde okunuyor.)*

## Adım 2: Sanal Makine Kurulumları (Provisioning)
Terraform kullanarak sanal makineleri (VM) ve ağ altyapısını oluşturmak için:

```bash
cd terraform/environments/production
terraform init  # Sadece ilk kullanımda
terraform apply -var-file="secret.tfvars"
```

*(Not: Desktop'ın veri diski, hostun ikinci NVMe'si `/dev/nvme0n1`'in tamamıdır
ve VM 102'ye doğrudan (passthrough) verilir — `modules/ubuntu_desktop` içindeki
`data_volume_id`. Host bu diski hiçbir zaman kendisi kullanmamalıdır.)*

Uygulamadan önce ne değişeceğini görmek için `apply` yerine
`terraform plan -var-file="secret.tfvars"` çalıştırın.

> **ubuntu-server repodan kaldırıldı (2026-10-03).** State'inizde hâlâ
> duruyorsa, bir sonraki `terraform apply` VM 101'i diskleriyle birlikte ve
> `local:import/ubuntu-26.04-server-cloudimg-amd64.qcow2` dosyasını **siler**.
> VM'i silmeden yalnızca Terraform'un takibinden çıkarmak isterseniz önce:
> `terraform state rm 'module.ubuntu_server_vm[0]' 'proxmox_download_file.ubuntu_cloud_image[0]'`

## Adım 3: Sanal Makine İç Konfigürasyonları (Ansible)
Sanal makineler ayağa kalktıktan sonra, işletim sistemi içi ayarları, paket
kurulumlarını ve disk bağlama işlemlerini yapmak için:

**Ubuntu Desktop için:**
```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml
```
*(Bu komut imajın üzerine yapılan değişiklikleri uygular: Brave ve Docker apt
depoları, elle kurulan paketler (NVIDIA 595-open sürücüsü dahil), snap'ler
(VS Code, Discord, Proton VPN), saat dilimi, PRIME modu, controller'ın SSH
anahtarı ve GNOME ayarları (dconf sistem varsayılanı olarak). Veri diskini
UUID ile `/mnt/data`'ya bağlar ve `~/Projects` bağlantısını kurar; diski asla
formatlamaz. Ayarların tamamı `inventories/production/group_vars/ubuntu_desktop.yml`
içinde.)*

Masaüstüne doğrudan bağlanılır: controller'ın çalıştığı makinede
`10.10.0.0/16 via 192.168.1.201` route'u olmalı (docs/network.md).

**Yeni bir desktop VM'inde tek seferlik hazırlık:** imajda openssh-server yok
ve GPU passthrough yüzünden ekranı Proxmox konsolu değil fiziksel monitördür.
Ansible'ın girebilmesi için o makinede bir kez:

```bash
sudo apt install -y openssh-server
install -d -m 700 ~/.ssh && cat >> ~/.ssh/authorized_keys   # controller'ın açık anahtarını yapıştırın
```

Sonrasında anahtarı da paketi de playbook korur.

**OPNsense / Firewall için:**
```bash
cd ansible
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml
```

`env $(grep ...)` öneki `.env`'den yalnızca iki API değişkenini o koşunun
ortamına koyar; kabukta kalıcı iz bırakmaz ve değerler komut satırına yazılmaz.
`. ../.env` **demeyin**: `proxmox_passwd` değerinde kabuğun işleyeceği bir
karakter var.

*(Modüller güvenlik duvarının üstünde değil, controller'da çalışır: REST API'yi
çağırırlar. Bu yüzden `opnsense` grubu `connection: local` ile koşar ve
interpreter olarak ansible'ı çalıştıran python'u — yani `.venv`'i — kullanır.)*

Her koşu önce API'nin yazamadığı ayarları (arayüz atamaları ve adresleri,
`WAN_GW`, hostname, çalışan servisler) okur; rolün `opnsense_baseline_*`
değerlerinden farklıysa hiçbir şey yazmadan durur.

## Kuru çalıştırma: canlıyla kod arasındaki fark

Üç playbook'un hepsine `--check --diff` eklenebilir ve hiçbir şey yazılmaz.
OPNsense için bu gerçek bir fark raporudur: okumalar gerçekten yapılır,
modüller yazmadan karşılaştırır; `changed` diyen her görev kod ile firewall
arasındaki bir farktır.

```bash
env $(grep '^OPNSENSE_API_' ../.env) ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/opnsense/site.yml --check --diff
```

Savepoint OPNsense 26.7'de yok (`-e opnsense_use_savepoint=true` koşuyu
bilerek durdurur). Firewall'a yazmadan önce güvenlik ağı olarak bir config
yedeği alın: System → Configuration → Backups.
