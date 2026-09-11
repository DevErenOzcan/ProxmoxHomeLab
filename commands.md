# Proxmox HomeLab Commands

Here are the commands for managing the Proxmox HomeLab environment:

### 1. Proxmox Configuration
To run the Proxmox configuration playbook:
```bash
ansible-playbook 01_proxmox_config/site.yml
```

### 2. VM Provisioning
To provision virtual machines using Terraform:
```bash
terraform apply 02_vm_provisioning/environments/local -var-file="secret.tfvars"
```

### 3. VM Configuration
To run the VM configuration playbook:
```bash
ansible-playbook 03_vm_config/site.yml
```