#!/usr/bin/env bash
#
# Adım 1: Proxmox Host Konfigürasyonu
#
# Bu komut Proxmox sunucusunun (host) kurulumunu ve ayarlarını yapar.
# Not: İlk kullanımda "ansible-galaxy collection install -r 01_proxmox_config/requirements.yml"
# komutunu çalıştırarak gerekli eklentileri indirmeyi unutmayın.

cd 01_proxmox_config && ansible-playbook site.yml
