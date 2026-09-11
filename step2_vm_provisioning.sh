#!/usr/bin/env bash
#
# Adım 2: Sanal Makine (VM) Kurulumları
#
# Bu komut Terraform kullanarak sanal makineleri ve ağ altyapısını kurar.
# Not: İlk kullanımda "terraform init" yapmanız gerekebilir.

cd 02_vm_provisioning/environments/local && terraform apply -var-file="secret.tfvars"
