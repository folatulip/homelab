# =====================================================================
# Talos Kubernetes cluster on Proxmox (3 nodes on "goose")
# =====================================================================

locals {
  talos_version    = "v1.14.4"
  cluster_name     = "geese-k8s"
  cluster_endpoint = "https://10.10.20.50:6443"
  gateway          = "10.10.20.1"
  vlan_id          = null # set to 20 if VMs on vmbr0 need a VLAN tag to land on 10.10.20.0/24
  proxmox_node     = "goose"

  talos_nodes = {
    talos-cp1 = { vm_id = 401, ip = "10.10.20.50", role = "controlplane", memory = 4096 }
    talos-w1  = { vm_id = 411, ip = "10.10.20.75", role = "worker", memory = 6144 }
    talos-w2  = { vm_id = 412, ip = "10.10.20.62", role = "worker", memory = 6144 }
  }

  controlplane_ip = local.talos_nodes["talos-cp1"].ip
}

# 1. Talos image (qemu guest agent baked in) → ISO on Proxmox

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = ["siderolabs/qemu-guest-agent"]
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = local.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
}

resource "proxmox_download_file" "talos_iso" {
  node_name    = local.proxmox_node
  datastore_id = "local"
  content_type = "iso"
  url          = data.talos_image_factory_urls.this.urls.iso
  file_name    = "talos-${local.talos_version}-nocloud-amd64.iso"
  overwrite    = false
}

# 2. VMs

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.talos_nodes

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = local.proxmox_node
  tags      = ["talos", "k8s", "prod"]
  on_boot   = true

  stop_on_destroy = true
  scsi_hardware   = "virtio-scsi-single"

  # Empty disk on first boot → falls through to the ISO.
  # After Talos installs itself → boots from disk.
  boot_order = ["scsi0", "ide0"]

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "x86-64-v2-AES" # Talos needs x86-64-v2, qemu64 won't boot
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide0"
  }

  network_device {
    bridge  = "vmbr0"
    vlan_id = local.vlan_id
  }

  operating_system {
    type = "l26"
  }

  # Talos "nocloud" reads this → static IP even in maintenance mode.
  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = local.gateway
      }
    }

    dns {
      servers = [local.gateway]
    }
  }
}

# 3. Talos config → apply → bootstrap

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_version
}

data "talos_machine_configuration" "this" {
  for_each = local.talos_nodes

  cluster_name     = local.cluster_name
  cluster_endpoint = local.cluster_endpoint
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_version

  # Talos >= 1.14: install settings live in the UnattendedInstallConfig
  # document; setting the legacy .machine.install alongside it is rejected.
  config_patches = [
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        # Pin our schematic so upgrades keep the qemu-guest-agent extension.
        image = data.talos_image_factory_urls.this.urls.installer
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/sda\""
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "this" {
  for_each   = local.talos_nodes
  depends_on = [proxmox_virtual_environment_vm.talos]

  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = local.controlplane_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = local.controlplane_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_client_configuration" "this" {
  cluster_name         = local.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.controlplane_ip]
  nodes                = [for n in local.talos_nodes : n.ip]
}

# 4. Outputs

output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}
