module "ubuntu_server_vm" {
  source = "../../modules/ubuntu_server"

  node_name      = var.node_name
  vm_id          = 100
  vm_name        = "ubuntu_server"
  ip_address     = "192.168.3.10/24"
  gateway        = "192.168.3.1"
  network_bridge = "vmbr1"
}

module "ubuntu_desktop_vm" {
  source = "../../modules/ubuntu_desktop"

  node_name      = var.node_name
  vm_id          = 101
  vm_name        = "ubuntu_desktop"
  ip_address     = "192.168.3.11/24"
  gateway        = "192.168.3.1"
  network_bridge = "vmbr1"
}