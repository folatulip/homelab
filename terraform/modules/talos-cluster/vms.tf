# One Proxmox VM per node. First boot: empty disk falls through to the ISO
# (Talos maintenance mode). After install: boots from scsi0.

resource "proxmox_virtual_environment_vm" "this" {
  for_each = var.nodes

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = each.value.proxmox_node
  tags      = concat(["talos", "k8s"], var.tags)
  on_boot   = true

  stop_on_destroy = true

  # Changing proxmox_node live-migrates the VM (disk copied to the target's
  # local-lvm) instead of destroy + recreate. The target node must also be in
  # module.talos_image proxmox_nodes so its ISO exists there.
  migrate         = true
  timeout_migrate = 1800
  scsi_hardware   = "virtio-scsi-single"
  boot_order      = ["scsi0", "ide0"]

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "x86-64-v2-AES" # Talos needs x86-64-v2, qemu64 won't boot
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = each.value.disk_size
    file_format  = "raw"
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  # Longhorn data disk. Talos formats it and mounts it at /var/mnt/longhorn
  # (patches/worker/longhorn-volume.yaml).
  dynamic "disk" {
    for_each = each.value.data_disk_size > 0 ? [each.value.data_disk_size] : []
    content {
      datastore_id = "local-lvm"
      interface    = "scsi1"
      size         = disk.value
      file_format  = "raw"
      iothread     = true
      discard      = "on"
      ssd          = true
    }
  }

  cdrom {
    file_id   = var.iso_ids[each.value.proxmox_node]
    interface = "ide0"
  }

  network_device {
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  operating_system {
    type = "l26"
  }

  # Talos nocloud reads this -> static IP even in maintenance mode.
  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.prefix_length}"
        gateway = var.gateway
      }
    }

    dns {
      servers = coalesce(var.dns_servers, [var.gateway])
    }
  }
}
