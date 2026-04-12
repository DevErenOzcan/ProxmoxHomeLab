# Proxmox IaC Homelab

Bu proje, bir Proxmox homelab ortamının altyapısını kod olarak (Infrastructure as Code - IaC) yönetmek için Ansible ve Terraform kullanmaktadır. İşletim sistemi seviyesi konfigürasyonlar (GPU passthrough vb.) Ansible ile, sanal makine ve kaynak yönetimi ise Terraform ile yapılmaktadır.

## Mimari Yaklaşım

- **Ansible**: Proxmox sunucularının temel ayarlarını (host hazırlığı, GPU passthrough için kernel parametreleri ve modül yüklemeleri) otomatize eder.
- **Terraform**: Proxmox üzerinde sanal makineleri (Ubuntu, Windows) oluşturur, konfigüre eder ve yaşam döngülerini yönetir. En güncel `bpg/proxmox` provider'ı kullanılmaktadır.

## Kullanım Rehberi

### Adım 1: Ansible ile Host Hazırlığı

Öncelikle Proxmox host makinenizi sanal makineler için hazır hale getirmeniz gerekmektedir. Özellikle GPU passthrough gibi donanım düzeyinde işlemler için host ayarları yapılmalıdır.

1. `ansible/inventory/hosts.yml` dosyasını kendi ortamınıza göre güncelleyin.
2. Ansible dizinine giderek Playbook'ları çalıştırın:

```bash
cd ansible

# Host hazırlığı playbook'u
ansible-playbook -i inventory/hosts.yml playbooks/01-host-prep.yml

# GPU Passthrough yapılandırması playbook'u (Gerekliyse)
ansible-playbook -i inventory/hosts.yml playbooks/02-gpu-passthrough.yml
```

> **Not:** `02-gpu-passthrough.yml` playbook'u otomatik olarak GRUB'u güncelleyecek ve IOMMU/VFIO ayarlarını uygulayacaktır. Bu ayarların tam olarak devreye girmesi için çalıştırdıktan sonra Proxmox host'unuzu **yeniden başlatmanız** gerekebilir.

### Adım 2: Terraform ile Sanal Makinelerin Oluşturulması

Host hazırlıkları tamamlandıktan sonra Terraform ile sanal makinelerinizi (Windows, Ubuntu vb.) oluşturabilirsiniz. Bu adımda ilgili modüller işletilerek sunucular konfigüre edilir.

1. `terraform/environments/local/` dizinine gidin:

```bash
cd terraform/environments/local
```

2. Ortamınıza özel gereksinimleri (örneğin `.tfvars` dosyası üzerinden) belirtin veya oluşturulan kaynakları `main.tf` ve `variables.tf` üzerinden gözden geçirin.

3. Terraform projesini ilklendirin:

```bash
terraform init
```

4. Yapılacak değişikliklerin planını görüntüleyin ve doğruluğunu teyit edin:

```bash
terraform plan
```

5. Değişiklikleri uygulayın (Onay vermeniz istenecektir):

```bash
terraform apply
```
