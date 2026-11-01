output "clusters" {
  value = {
    trusted = module.trusted.info
    dmz     = try(module.dmz[0].info, null)
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

output "dmz_talosconfig" {
  value     = try(module.dmz[0].talosconfig, null)
  sensitive = true
}

output "dmz_kubeconfig" {
  value     = try(module.dmz[0].kubeconfig, null)
  sensitive = true
}

# For `talosctl upgrade --image` after the extension list changes.
output "installer_image" {
  value = module.talos_image.installer_image
}
