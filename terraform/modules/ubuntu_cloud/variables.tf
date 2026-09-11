variable "node_name" {
  description = "Proxmox node name"
  type        = string
}

variable "vm_id" {
  description = "VM ID"
  type        = number
}

variable "vm_name" {
  description = "VM name"
  type        = string
}

variable "description" {
  description = "Free-text description shown in the Proxmox UI"
  type        = string
  default     = "Ubuntu cloud image guest. Managed by Terraform."
}

variable "tags" {
  description = "Proxmox tags"
  type        = list(string)
  default     = ["ubuntu", "terraform"]
}

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------
variable "cloud_image_file_id" {
  description = <<-EOT
    Volume ID of the Ubuntu cloud image, e.g.
    local:import/ubuntu-26.04-server-cloudimg-amd64.qcow2.

    This must be a CLOUD IMAGE, not an installer ISO. An installer ISO has no
    filesystem to boot from and no cloud-init, so attaching one as the disk
    produces a VM that boots to nothing and silently ignores ip_address. That
    was the bug in the modules this one replaces.
  EOT
  type        = string
}

# ---------------------------------------------------------------------------
# Sizing
# ---------------------------------------------------------------------------
variable "cores" {
  description = "vCPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "RAM in MB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = <<-EOT
    Disk size in GB. The cloud image is about 3.5 GB virtual; this grows it on
    first boot. Thin-provisioned on local-lvm, so it costs only what is used.
  EOT
  type        = number
  default     = 40
}

variable "datastore_id" {
  description = "Datastore for the OS disk and the cloud-init drive"
  type        = string
  default     = "local-lvm"
}

variable "cpu_type" {
  description = "'host' passes the real CPU flags through; fine on a single node"
  type        = string
  default     = "host"
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
variable "ip_address" {
  description = "Static address in CIDR form, e.g. 10.10.10.10/24. Use \"dhcp\" to let OPNsense assign one."
  type        = string
}

variable "gateway" {
  description = "Default gateway - the OPNsense interface for this segment"
  type        = string
}

variable "network_bridge" {
  description = "Bridge to attach to"
  type        = string
}

variable "dns_servers" {
  description = <<-EOT
    Resolvers for the guest. Defaults to the gateway, because OPNsense runs
    Unbound and the guests are firewalled off from the home network's resolver.
  EOT
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Credentials
# ---------------------------------------------------------------------------
variable "username" {
  description = "Cloud-init user"
  type        = string
  default     = "ubuntu"
}

variable "password" {
  description = "Password for that user. Empty means key-only access."
  type        = string
  default     = ""
  sensitive   = true
}

variable "ssh_public_keys" {
  description = "Public keys authorised for the cloud-init user"
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# Behaviour
# ---------------------------------------------------------------------------
variable "cloud_init_upgrade" {
  description = <<-EOT
    Run a package upgrade on first boot. Off by default: until OPNsense is
    installed and routing, these guests have no way out and cloud-init would
    just stall waiting for the network.
  EOT
  type        = bool
  default     = false
}

variable "agent_enabled" {
  description = <<-EOT
    Wait for qemu-guest-agent. Ubuntu cloud images ship it and it talks over
    virtio-serial, so it works with no network. Turn off if an apply ever hangs
    waiting for a guest that will not boot.
  EOT
  type        = bool
  default     = true
}

variable "started" {
  description = "Whether Terraform keeps the VM running"
  type        = bool
  default     = true
}

variable "startup_order" {
  description = "Proxmox boot order. The firewall is 1, so guests start at 2."
  type        = number
  default     = 2
}

variable "startup_up_delay" {
  description = "Seconds to wait after this VM before starting the next one"
  type        = number
  default     = 0
}
