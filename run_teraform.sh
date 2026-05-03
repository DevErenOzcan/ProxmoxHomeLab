#!/bin/bash
echo -e "\n${GREEN}=== Terraform: Sanal Makinelerin Kurulumu ===${NC}"
cd ../terraform/environments/local
echo "Terraform Initialize ediliyor..."
terraform init -v
echo "Terraform Apply çalışıyor..."
terraform apply -auto-approve

echo -e "\n${GREEN}=== Tüm işlemler başarıyla tamamlandı! ===${NC}"