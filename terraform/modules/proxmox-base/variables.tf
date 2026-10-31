variable "dns" {
  description = "Default DNS for every node (max 3 servers). Override per node with nodes[*].dns."
  type = object({
    domain  = string
    servers = list(string)
  })
}

variable "timezone" {
  type    = string
  default = "UTC"
}

variable "nodes" {
  description = "Proxmox node name => host network settings."
  type = map(object({
    ip            = string # management IP, lives on the bridge
    prefix_length = optional(number, 24)
    gateway       = string
    bridge        = optional(string, "vmbr0")
    bridge_ports  = list(string) # physical NIC(s) behind the bridge
    vlan_aware    = optional(bool, true)
    vlans         = optional(list(number), []) # bridge-vids; empty = Proxmox default (2-4094)
    mtu           = optional(number)

    # Optional host-side VLAN interfaces, e.g. to give the node an IP on a VLAN.
    # name => { vlan, address (CIDR) }. Interface becomes "<bridge>.<vlan>".
    vlan_interfaces = optional(map(object({
      vlan    = number
      address = optional(string)
      comment = optional(string)
    })), {})

    dns = optional(object({
      domain  = string
      servers = list(string)
    }))
  }))
}

variable "nas_storages" {
  description = "Storage id => NAS share. type = \"cifs\" (SMB) or \"nfs\"."
  type = map(object({
    type     = string
    server   = string
    share    = optional(string) # cifs
    export   = optional(string) # nfs
    username = optional(string) # cifs
    domain   = optional(string) # cifs
    content  = optional(set(string), ["backup", "iso", "vztmpl"])
    nodes    = optional(set(string)) # null = all nodes
    options  = optional(string)      # mount options
    subdir   = optional(string)      # cifs subdirectory
    disable  = optional(bool, false)

    # Retention for "backup" content.
    backups = optional(object({
      keep_last    = optional(number)
      keep_daily   = optional(number)
      keep_weekly  = optional(number)
      keep_monthly = optional(number)
      keep_yearly  = optional(number)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for s in var.nas_storages : contains(["cifs", "nfs"], s.type)])
    error_message = "nas_storages[*].type must be \"cifs\" or \"nfs\"."
  }
  validation {
    condition = alltrue([for s in var.nas_storages :
      s.type == "cifs" ? (s.share != null && s.username != null) : s.export != null
    ])
    error_message = "cifs storages need share + username; nfs storages need export."
  }
}

variable "nas_passwords" {
  description = "Storage id => SMB password (set in terraform.tfvars)."
  type        = map(string)
  default     = {}
  sensitive   = true
}

variable "cluster_options" {
  description = "Datacenter-wide options. Unset (null) fields are left to Proxmox."
  type = object({
    description        = optional(string)
    keyboard           = optional(string)
    language           = optional(string)
    console            = optional(string) # applet | vv | html5 | xtermjs
    mac_prefix         = optional(string)
    email_from         = optional(string)
    http_proxy         = optional(string)
    migration_type     = optional(string) # secure | insecure
    migration_cidr     = optional(string)
    ha_shutdown_policy = optional(string) # freeze | failover | migrate | conditional
    max_workers        = optional(number)
    next_id = optional(object({
      lower = optional(number)
      upper = optional(number)
    }))
  })
  default = {}
}
