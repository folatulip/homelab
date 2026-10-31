# Secrets -> per-node machine config -> push to nodes -> bootstrap etcd -> kubeconfig

locals {
  controlplane_ips = [for n in var.nodes : n.ip if n.role == "controlplane"]
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "this" {
  for_each = var.nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.endpoint_ip}:6443"
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version

  # Talos >= 1.14: install settings live in the UnattendedInstallConfig
  # document; setting the legacy .machine.install alongside it is rejected.
  config_patches = concat([
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer = {
        image = var.installer_image
      }
      provisioning = {
        diskSelector = {
          match = "disk.dev_path == \"/dev/sda\""
        }
      }
    })
    ], each.value.role == "worker" ? [
    # Directory for local-path-provisioner's PersistentVolumes
    # (kubernetes/infrastructure/local-path-provisioner), created on the
    # EPHEMERAL partition at /var/mnt/local-path-provisioner. User volumes under
    # /var/mnt are the only host paths the kubelet sees; Talos >= 1.14 dropped
    # .machine.kubelet.extraMounts (it conflicts with the KubeletConfig document).
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UserVolumeConfig"
      name       = "local-path-provisioner"
      volumeType = "directory"
    })
  ] : [])
}

resource "talos_machine_configuration_apply" "this" {
  for_each   = var.nodes
  depends_on = [proxmox_virtual_environment_vm.this]

  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  node                 = var.endpoint_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [talos_machine_bootstrap.this]

  node                 = var.endpoint_ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = [for n in var.nodes : n.ip]
}
