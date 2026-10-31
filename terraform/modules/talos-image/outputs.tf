output "installer_image" {
  description = "Installer image Talos writes to disk (keeps our extensions on upgrade)."
  value       = data.talos_image_factory_urls.this.urls.installer
}

output "iso_ids" {
  description = "Map of Proxmox node name => ISO file id."
  value       = { for node, f in proxmox_download_file.iso : node => f.id }
}
