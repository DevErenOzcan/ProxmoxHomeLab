# Ubuntu Server ISO'sunu indir
resource "proxmox_virtual_environment_download_file" "ubuntu_server_iso" {
  content_type = "iso"
  datastore_id = "local" # ISO'ların tutulduğu datastore (genelde 'local'dir)
  node_name    = var.node_name
  url          = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
  file_name    = "ubuntu-26.04-live-server-amd64.iso"
}

# Ubuntu Desktop ISO'sunu indir
resource "proxmox_virtual_environment_download_file" "ubuntu_desktop_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = var.node_name
  url          = "https://releases.ubuntu.com/26.04/ubuntu-26.04-desktop-amd64.iso"
  file_name    = "ubuntu-26.04-desktop-amd64.iso"
}

# Ağın Kalbi: Router Modülü
module "network_router" {
  source             = "../../modules/router"
  proxmox_node       = var.node_name
  vm_id              = 99 # Router için kullanmak istediğin ID
  router_template_id = 900 # Proxmox'taki pfSense/OPNsense template ID'n
  wan_mac_address    = "AA:BB:CC:DD:EE:FF" # Modemde 192.168.1.200'e rezerve edeceğin MAC
}

# Sunucu Makinesi
module "ubuntu_server_vm" {
  source         = "../../modules/ubuntu_server"
  node_name      = var.node_name
  vm_id          = 100
  vm_name        = "ubuntu_server"
  ip_address     = "192.168.3.10/24"
  gateway        = "192.168.3.1" # Bu gateway ip'sini pfSense'in LAN bacağına vermelisin
  network_bridge = "vmbr1"
  
  depends_on = [module.network_router]
}

# Masaüstü Makinesi
module "ubuntu_desktop_vm" {
  source         = "../../modules/ubuntu_desktop"
  node_name      = var.node_name
  vm_id          = 101
  vm_name        = "ubuntu_desktop"
  ip_address     = "192.168.3.11/24"
  gateway        = "192.168.3.1" # Bu gateway ip'sini pfSense'in LAN bacağına vermelisin
  network_bridge = "vmbr1"
  
  depends_on = [module.network_router]
}