terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # decompression_algorithm = "bz2" (the OPNsense installer download) needs
      # a recent provider. .terraform.lock.hcl pins the exact version.
      version = "~> 0.112"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true # the homelab's self-signed certificate
}
