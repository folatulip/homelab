# =====================================================================
# Homelab Kubernetes clusters (Talos on Proxmox cluster "geese")
# =====================================================================

locals {
  talos_version = "v1.14.4"
}

# One Talos image shared by all clusters.
module "talos_image" {
  source        = "./modules/talos-image"
  talos_version = local.talos_version
  proxmox_nodes = ["goose"] # add "goose2" once a VM is placed there

  # iscsi-tools + util-linux-tools: required by Longhorn (iSCSI, fstrim, nsenter).
  # Changing this list changes the installer image: roll nodes with
  # `talosctl upgrade --image <terraform output installer_image>` after apply.
  extensions = [
    "siderolabs/qemu-guest-agent",
    "siderolabs/iscsi-tools",
    "siderolabs/util-linux-tools",
  ]
}

# --- Trusted cluster (VLAN 20, untagged on vmbr0) ---------------------
module "trusted" {
  source = "./modules/talos-cluster"

  cluster_name  = "geese-k8s"
  talos_version = local.talos_version
  endpoint_ip   = "10.10.20.50"
  gateway       = "10.10.20.1"
  vlan_id       = null
  tags          = ["prod", "trusted"]

  installer_image = module.talos_image.installer_image
  iso_ids         = module.talos_image.iso_ids

  nodes = {
    talos-cp1 = { vm_id = 401, ip = "10.10.20.50", role = "controlplane", proxmox_node = "goose", memory = 4096 }
    talos-w1  = { vm_id = 411, ip = "10.10.20.75", role = "worker", proxmox_node = "goose", memory = 6144, data_disk_size = 50 }
    talos-w2  = { vm_id = 412, ip = "10.10.20.62", role = "worker", proxmox_node = "goose", memory = 6144, data_disk_size = 50 }
  }
}

# --- DMZ cluster ----
# Also add "goose2" to module.talos_image.proxmox_nodes if used below.
#
# module "dmz" {
#   source = "./modules/talos-cluster"
#
#   cluster_name  = "dmz"
#   talos_version = local.talos_version
#   endpoint_ip   = "10.10.30.50"
#   gateway       = "10.10.30.1"
#   vlan_id       = 30
#   tags          = ["prod", "dmz"]
#
#   installer_image = module.talos_image.installer_image
#   iso_ids         = module.talos_image.iso_ids
#
#   nodes = {
#     dmz-cp1 = { vm_id = 501, ip = "10.10.30.50", role = "controlplane", proxmox_node = "goose2" }
#     dmz-w1  = { vm_id = 511, ip = "10.10.30.51", role = "worker", proxmox_node = "goose2" }
#     dmz-w2  = { vm_id = 512, ip = "10.10.30.52", role = "worker", proxmox_node = "goose2" }
#   }
# }
