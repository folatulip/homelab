# Builds one Talos image (via Image Factory) and downloads its boot ISO
# to every Proxmox node that will run Talos VMs. Shared by all clusters.

resource "talos_image_factory_schematic" "this" {
  schematic = yamlencode({
    customization = {
      systemExtensions = {
        officialExtensions = var.extensions
      }
    }
  })
}

data "talos_image_factory_urls" "this" {
  talos_version = var.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "nocloud"
  architecture  = "amd64"
}

# local storage is per-node, so each Proxmox node needs its own copy.
resource "proxmox_download_file" "iso" {
  for_each = var.proxmox_nodes

  node_name    = each.key
  datastore_id = "local"
  content_type = "iso"
  url          = data.talos_image_factory_urls.this.urls.iso
  # Schematic id in the name: a new extension list gets a new file, so the
  # VMs switch to it before the old ISO is deleted.
  file_name = "talos-${var.talos_version}-${substr(talos_image_factory_schematic.this.id, 0, 8)}-nocloud-amd64.iso"
  overwrite = false

  lifecycle {
    create_before_destroy = true
  }
}
