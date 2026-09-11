terraform {
  required_version = ">= 1.5"

  required_providers {
    proxmox = {
      source = "bpg/proxmox"
      # 0.60.0 was pinned here before. It rejects decompression_algorithm =
      # "bz2", which the OPNsense installer download needs (Proxmox itself has
      # supported bz2 for a long time - the limit was the provider).
      version = "~> 0.112"
    }
  }
}

provider "proxmox" {
  endpoint = var.proxmox_endpoint
  username = var.proxmox_username
  password = var.proxmox_password
  # api_token = var.proxmox_api_token # Optional: an API token can be used instead of a password
  insecure = true # Accept the self-signed certificate of the homelab
}
