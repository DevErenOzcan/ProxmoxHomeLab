# Proxmox HomeLab Commands

Yönetim ve kurulum komutları tamamen standart CLI araçlarına dayanır. 
Aşağıdaki komutları doğrudan terminalinizden kopyalayıp çalıştırabilirsiniz.

## Adım 1: Proxmox Host Konfigürasyonu
Proxmox sunucusunun temel ayarlarını, depolarını, ağ köprülerini (bridge) ve GPU Passthrough ayarlarını yapmak için:

```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventories/production/hosts.yml playbooks/proxmox/site.yml
```

*(Not: Windows üzerinden WSL ile (/mnt/c/...) çalışıyorsanız, dosya yetkilerinden kaynaklı `ansible.cfg` uyarılarını aşmak için komutların başında `ANSIBLE_CONFIG=ansible.cfg` kullanılması zorunludur.)*

*(Not: İlk çalıştırmadan önce `ansible-galaxy collection install -r requirements.yml` komutu ile gerekli Ansible eklentilerini kurduğunuzdan emin olun.)*

## Adım 2: Sanal Makine Kurulumları (Provisioning)
Terraform kullanarak sanal makineleri (VM) ve ağ altyapısını oluşturmak için:

```bash
cd terraform/environments/production
terraform init  # Sadece ilk kullanımda
terraform apply -var-file="secret.tfvars"
```

*(Not: Immutable Desktop senaryosu için Proxmox üzerinden bağımsız oluşturduğunuz veri diskinin ID'sini `secret.tfvars` veya `variables.tf` içinde `data_volume_id` olarak belirtmeyi unutmayın.)*

## Adım 3: Sanal Makine İç Konfigürasyonları (Ansible)
Sanal makineler ayağa kalktıktan sonra, işletim sistemi içi ayarları, paket kurulumlarını ve disk bağlama işlemlerini yapmak için:

**Ubuntu Desktop için:**
```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventories/production/hosts.yml playbooks/ubuntu_desktop/site.yml
```
*(Bu komut, masaüstü ortamını kurar ve bağımsız Data Volume diskinizi otomatik olarak `/mnt/data` klasörüne mount edip kullanıcı klasörlerinizi symlink ile bağlar.)*

**OPNsense / Firewall için:**
```bash
cd ansible
ANSIBLE_CONFIG=ansible.cfg ansible-playbook -i inventories/production/hosts.yml playbooks/opnsense/site.yml
```