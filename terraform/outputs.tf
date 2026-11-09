output "clusters" {
  value = {
    geese = module.geese.info
  }
}

# terraform output -raw geese_kubeconfig > ~/.kube/k8s-geese.yaml
output "geese_talosconfig" {
  value     = module.geese.talosconfig
  sensitive = true
}

output "geese_kubeconfig" {
  value     = module.geese.kubeconfig
  sensitive = true
}

# For `talosctl upgrade --image` after the extension list changes.
output "installer_image" {
  value = module.talos_image.installer_image
}
