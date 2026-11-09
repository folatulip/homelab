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

# --- k8s-geese: one cluster, trusted + DMZ nodes (ADR 0001) ----------
# Trusted nodes on VLAN 20 (untagged), DMZ nodes on VLAN 50. Cilium replaces
# flannel and kube-proxy: Talos boots it with no CNI, then
# scripts/bootstrap-cilium.sh installs it and Flux takes over.
# Same sizes k8s-trusted had, plus one DMZ node per host. Changing memory
# reboots the VM (Proxmox, no hotplug).
module "geese" {
  source = "./modules/talos-cluster"

  cluster_name  = "k8s-geese"
  talos_version = local.talos_version
  endpoint_ip   = "10.10.20.60"
  gateway       = "10.10.20.1"
  vlan_id       = null
  tags          = ["prod", "geese"]

  allow_scheduling_on_control_planes = true
  cni                                = "none"
  kube_proxy                         = false

  installer_image = module.talos_image.installer_image
  iso_ids         = module.talos_image.iso_ids

  nodes = {
    k8s-geese-cp1  = { vm_id = 601, ip = "10.10.20.60", role = "controlplane", proxmox_node = "goose", memory = 12288, cores = 4, data_disk_size = 50, zone = "trusted" }
    k8s-geese-w1   = { vm_id = 611, ip = "10.10.20.61", role = "worker", proxmox_node = "goose2", memory = 6144, data_disk_size = 50, zone = "trusted" }
    k8s-geese-dmz1 = { vm_id = 651, ip = "10.10.50.60", role = "worker", proxmox_node = "goose", memory = 3072, vlan_id = 50, gateway = "10.10.50.1", zone = "dmz" }
    k8s-geese-dmz2 = { vm_id = 652, ip = "10.10.50.61", role = "worker", proxmox_node = "goose2", memory = 3072, vlan_id = 50, gateway = "10.10.50.1", zone = "dmz" }
  }
}
