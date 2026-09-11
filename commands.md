for proxmox configs : ansible-playbook 01_proxmox_config/site.yml
for vm provisioning : terraform apply 02_vm_provisioning/environments/local -var-file="secret.tfvars"
for vm configs: ansible-playbook 03_vm_config/site.yml