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

*(Not: Immutable Desktop senaryosu için Proxmox üzerinden bağımsız oluşturduğunuz veri diskinin ID'sini `secret.tfvars` veya `variables.tf` içinde `data_volume_id` olarak belirtmeyi unutmayın.)*

## Adım 3: Sanal Makine İç Konfigürasyonları (Ansible)
Sanal makineler ayağa kalktıktan sonra, işletim sistemi içi ayarları, paket
kurulumlarını ve disk bağlama işlemlerini yapmak için:

**Ubuntu Desktop için:**
```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook playbooks/ubuntu_desktop/site.yml
```
*(Bu komut, masaüstü ortamını kurar ve bağımsız Data Volume diskinizi otomatik olarak `/mnt/data` klasörüne mount edip kullanıcı klasörlerinizi symlink ile bağlar.)*

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

Savepoint varsayılan olarak kapalı; kilitlenmeye karşı ağ isterseniz
`-e opnsense_use_savepoint=true` ekleyin.
