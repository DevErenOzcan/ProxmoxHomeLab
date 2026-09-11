#!/usr/bin/env bash
#
# Adım 3: Sanal Makine Konfigürasyonları
#
# Bu komut oluşturulan sanal makinelerin iç ayarlarını ve paket kurulumlarını yapar.

cd 03_vm_config && ansible-playbook site.yml
