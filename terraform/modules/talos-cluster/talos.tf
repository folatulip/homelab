# Secrets -> per-node machine config -> push to nodes -> bootstrap etcd -> kubeconfig

locals {
  controlplane_ips = [for n in var.nodes : n.ip if n.role == "controlplane"]

  patches = {
    for dir in ["common", "controlplane", "worker", "data-disk", "schedulable-controlplane", "cni-none", "no-kube-proxy", "zone-dmz"] : dir => [
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
  # node, the folder matching the node's role, and data-disk/ for nodes
  # with a data disk. schedulable-controlplane/ lets control planes run
  # regular pods when allow_scheduling_on_control_planes = true.
  # cni-none/ and no-kube-proxy/ only touch control plane documents.
  config_patches = concat(
    local.patches["common"],
    local.patches[each.value.role],
    each.value.data_disk_size > 0 ? local.patches["data-disk"] : [],
    each.value.role == "controlplane" && var.allow_scheduling_on_control_planes ? local.patches["schedulable-controlplane"] : [],
    each.value.role == "controlplane" && var.cni == "none" ? local.patches["cni-none"] : [],
    each.value.role == "controlplane" && !var.kube_proxy ? local.patches["no-kube-proxy"] : [],
    each.value.zone == "dmz" ? local.patches["zone-dmz"] : [],
  )
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

# Zone label, set as admin. Kubelets can't set node-restriction.kubernetes.io/*
# labels on themselves (NodeRestriction), so Talos can't either: it writes node
# labels with the node's own credentials. Being admin-only is the point: a
# compromised DMZ node can't relabel itself as trusted.
# Runs kubectl on the machine doing the apply. If a node is reinstalled, its
# Node object is new: re-run with `terraform apply -replace=<this resource>`.
resource "terraform_data" "zone_label" {
  for_each   = { for name, n in var.nodes : name => n.zone if n.zone != null }
  depends_on = [talos_cluster_kubeconfig.this]

  triggers_replace = [each.key, each.value]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      kubeconfig=$(mktemp)
      trap 'rm -f "$kubeconfig"' EXIT
      printf '%s' "$KUBECONFIG_DATA" > "$kubeconfig"

      # The node only exists once its kubelet has registered
      kubectl --kubeconfig "$kubeconfig" wait --for=create "node/$NODE" --timeout=15m
      kubectl --kubeconfig "$kubeconfig" label node "$NODE" --overwrite "node-restriction.kubernetes.io/zone=$ZONE"
    EOT

    environment = {
      KUBECONFIG_DATA = talos_cluster_kubeconfig.this.kubeconfig_raw
      NODE            = each.key
      ZONE            = each.value
    }
  }
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.controlplane_ips
  nodes                = [for n in var.nodes : n.ip]
}
