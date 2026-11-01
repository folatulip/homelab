output "talosconfig" {
  value     = data.talos_client_configuration.this.talos_config
  sensitive = true
}

output "kubeconfig" {
  value     = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive = true
}

output "info" {
  value = {
    cluster_name = var.cluster_name
    endpoint     = "https://${var.endpoint_ip}:6443"
    vlan_id      = var.vlan_id
    gateway      = var.gateway
    nodes = {
      for name, vm in proxmox_virtual_environment_vm.this : name => {
        vm_id        = vm.vm_id
        ip           = var.nodes[name].ip
        role         = var.nodes[name].role
        proxmox_node = vm.node_name
        cores        = var.nodes[name].cores
        memory       = var.nodes[name].memory
        disk_size    = var.nodes[name].disk_size
        data_disk    = var.nodes[name].data_disk_size
      }
    }
  }
}
