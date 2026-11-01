# =====================================================================
# Homelab Kubernetes clusters (Talos on Proxmox cluster "geese")
# Proxmox nodes: goose = goose-s1-pve, goose2 = goose-s2-pve. Each cluster has
# one node per host.
# =====================================================================

locals {
  talos_version = "v1.14.4"
}

# One Talos image shared by all clusters.
module "talos_image" {
  source        = "./modules/talos-image"
  talos_version = local.talos_version
  proxmox_nodes = ["goose", "goose2"]

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
# cp1 is control plane + worker. Longhorn keeps 2 replicas, one per host.
module "trusted" {
  source = "./modules/talos-cluster"

  cluster_name  = "k8s-trusted"
  talos_version = local.talos_version
  endpoint_ip   = "10.10.20.50"
  gateway       = "10.10.20.1"
  vlan_id       = null
  tags          = ["prod", "trusted"]

  allow_scheduling_on_control_planes = true

  installer_image = module.talos_image.installer_image
  iso_ids         = module.talos_image.iso_ids

  nodes = {
    k8s-trusted-cp1 = { vm_id = 401, ip = "10.10.20.50", role = "controlplane", proxmox_node = "goose", memory = 12288, cores = 4, data_disk_size = 50 }
    k8s-trusted-w1  = { vm_id = 411, ip = "10.10.20.51", role = "worker", proxmox_node = "goose2", memory = 6144, data_disk_size = 50 }
  }
}

# --- DMZ cluster (VLAN 50, tagged on vmbr0) ---------------------------
# Off until VLAN 50 exists in UniFi and is tagged on both hosts' switch
# ports. Then set dmz_enabled = true (also adds VLAN 50 to the host bridges
# in proxmox.tf) and apply.
locals {
  dmz_enabled = false
}

module "dmz" {
  source = "./modules/talos-cluster"
  count  = local.dmz_enabled ? 1 : 0

  cluster_name  = "k8s-dmz"
  talos_version = local.talos_version
  endpoint_ip   = "10.10.50.50"
  gateway       = "10.10.50.1"
  vlan_id       = 50
  tags          = ["prod", "dmz"]

  allow_scheduling_on_control_planes = true

  installer_image = module.talos_image.installer_image
  iso_ids         = module.talos_image.iso_ids

  nodes = {
    k8s-dmz-1 = { vm_id = 501, ip = "10.10.50.50", role = "controlplane", proxmox_node = "goose", memory = 4096 }
    k8s-dmz-2 = { vm_id = 511, ip = "10.10.50.51", role = "worker", proxmox_node = "goose2", memory = 3072 }
  }
}
