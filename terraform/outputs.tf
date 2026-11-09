output "clusters" {
  value = {
    trusted = module.trusted.info
  }
}

# terraform output -raw trusted_kubeconfig > ~/.kube/config
output "trusted_talosconfig" {
  value     = module.trusted.talosconfig
  sensitive = true
}

output "trusted_kubeconfig" {
  value     = module.trusted.kubeconfig
  sensitive = true
}

# For `talosctl upgrade --image` after the extension list changes.
output "installer_image" {
  value = module.talos_image.installer_image
}
