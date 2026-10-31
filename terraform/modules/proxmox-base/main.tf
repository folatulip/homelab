# Host-level Proxmox config: per-node network/DNS/time, NAS storages,
# datacenter options. Cluster creation/join is NOT handled here.

locals {
  vlan_interfaces = merge([
    for node, n in var.nodes : {
      for name, v in n.vlan_interfaces : "${node}/${name}" => merge(v, {
        node   = node
        bridge = n.bridge
      })
    }
  ]...)
}

# --- Network ---------------------------------------------------------
# WARNING: this bridge carries the node's management IP. A wrong value
# here cuts you off from the node. Run `terraform plan` and read it.

resource "proxmox_network_linux_bridge" "this" {
  for_each = var.nodes

  node_name  = each.key
  name       = each.value.bridge
  address    = "${each.value.ip}/${each.value.prefix_length}"
  gateway    = each.value.gateway
  ports      = each.value.bridge_ports
  vlan_aware = each.value.vlan_aware
  vids       = each.value.vlan_aware && length(each.value.vlans) > 0 ? join(" ", each.value.vlans) : null
  mtu        = each.value.mtu
}

resource "proxmox_network_linux_vlan" "this" {
  for_each   = local.vlan_interfaces
  depends_on = [proxmox_network_linux_bridge.this]

  node_name = each.value.node
  name      = "${each.value.bridge}.${each.value.vlan}"
  address   = each.value.address
  comment   = each.value.comment
}

# --- DNS / time ------------------------------------------------------

resource "proxmox_virtual_environment_dns" "this" {
  for_each = var.nodes

  node_name = each.key
  domain    = coalesce(each.value.dns, var.dns).domain
  servers   = coalesce(each.value.dns, var.dns).servers
}

resource "proxmox_virtual_environment_time" "this" {
  for_each = var.nodes

  node_name = each.key
  time_zone = var.timezone
}

# --- NAS storage -----------------------------------------------------

resource "proxmox_storage_cifs" "this" {
  for_each = { for id, s in var.nas_storages : id => s if s.type == "cifs" }

  id           = each.key
  server       = each.value.server
  share        = each.value.share
  username     = each.value.username
  password     = var.nas_passwords[each.key]
  domain       = each.value.domain
  subdirectory = each.value.subdir
  options      = each.value.options
  content      = each.value.content
  nodes        = each.value.nodes
  disable      = each.value.disable

  dynamic "backups" {
    for_each = each.value.backups[*]
    content {
      keep_last    = backups.value.keep_last
      keep_daily   = backups.value.keep_daily
      keep_weekly  = backups.value.keep_weekly
      keep_monthly = backups.value.keep_monthly
      keep_yearly  = backups.value.keep_yearly
    }
  }
}

resource "proxmox_storage_nfs" "this" {
  for_each = { for id, s in var.nas_storages : id => s if s.type == "nfs" }

  id      = each.key
  server  = each.value.server
  export  = each.value.export
  options = each.value.options
  content = each.value.content
  nodes   = each.value.nodes
  disable = each.value.disable

  dynamic "backups" {
    for_each = each.value.backups[*]
    content {
      keep_last    = backups.value.keep_last
      keep_daily   = backups.value.keep_daily
      keep_weekly  = backups.value.keep_weekly
      keep_monthly = backups.value.keep_monthly
      keep_yearly  = backups.value.keep_yearly
    }
  }
}

# --- Datacenter options ----------------------------------------------

resource "proxmox_cluster_options" "this" {
  description        = var.cluster_options.description
  keyboard           = var.cluster_options.keyboard
  language           = var.cluster_options.language
  console            = var.cluster_options.console
  mac_prefix         = var.cluster_options.mac_prefix
  email_from         = var.cluster_options.email_from
  http_proxy         = var.cluster_options.http_proxy
  migration_type     = var.cluster_options.migration_type
  migration_cidr     = var.cluster_options.migration_cidr
  ha_shutdown_policy = var.cluster_options.ha_shutdown_policy
  max_workers        = var.cluster_options.max_workers
  next_id            = var.cluster_options.next_id
}
