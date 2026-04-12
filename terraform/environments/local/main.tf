module "ubuntu_desktop_vm" {
  source = "../../modules/ubuntu_desktop"

  node_name = var.node_name
  vm_id     = 101
  vm_name   = "ubuntu_desktop"
}
