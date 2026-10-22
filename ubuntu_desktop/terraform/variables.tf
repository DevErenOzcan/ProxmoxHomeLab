variable "proxmox_password" {
  description = "Password of root@pam on the Proxmox host. From secret.tfvars (git-ignored): -var-file=secret.tfvars"
  type        = string
  sensitive   = true
}

variable "os_image" {
  description = <<-EOT
    The disk image a new OS disk is imported from: a file on the host's
    "local" storage (content type "import"). Only used when the VM is created;
    the running VM ignores it. README.md, "The disk image", says how to put a
    current build there.
  EOT
  type        = string
  default     = "local:import/ubuntu-desktop-26.04-amd64.qcow2"
}
