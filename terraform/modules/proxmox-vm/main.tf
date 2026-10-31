resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  node_name = var.node
  vm_id     = var.vm_id
  tags      = var.tags

  clone {
    vm_id = var.template_id
  }

  agent {
    enabled = true
  }

  cpu { cores = var.cores }
  memory { dedicated = var.memory }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = var.disk_size
  }

  network_device { bridge = "vmbr0" }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }
    user_account {
      username = "goose"
      keys     = [file("~/.ssh/id_ed25519.pub")]
    }
  }
}