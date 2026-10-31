output "clusters" {
  value = {
    trusted = module.trusted.info
    # dmz   = module.dmz.info
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

# output "dmz_talosconfig" {
#   value     = module.dmz.talosconfig
#   sensitive = true
# }
#
# output "dmz_kubeconfig" {
#   value     = module.dmz.kubeconfig
#   sensitive = true
# }
