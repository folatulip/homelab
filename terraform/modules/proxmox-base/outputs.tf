output "node_names" {
  value = toset(keys(var.nodes))
}

output "storage_ids" {
  value = keys(var.nas_storages)
}
