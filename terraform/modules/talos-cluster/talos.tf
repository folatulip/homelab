# Secrets -> per-node machine config -> push to nodes -> bootstrap etcd -> kubeconfig

locals {
  controlplane_ips = [for n in var.nodes : n.ip if n.role == "controlplane"]

  patches = {
    for dir in ["common", "controlplane", "worker"] : dir => [
      for f in sort(fileset("${path.module}/patches/${dir}", "*.yaml")) :
      templatefile("${path.module}/patches/${dir}/${f}", { installer_image = var.installer_image })
    ]
  }
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

  # YAML patches in ./patches (see patches/README.md): common/ for every
  # node, then the folder matching the node's role.
  config_patches = concat(local.patches["common"], local.patches[each.value.role])
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
