terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.60.0"
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
