variable "cluster_name" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "endpoint_ip" {
  type        = string
  description = "IP of the control plane node used as the Kubernetes API endpoint."
}

variable "gateway" {
  type = string
}

variable "dns_servers" {
  type        = list(string)
  default     = null
  description = "Defaults to [gateway]."
}

variable "prefix_length" {
  type    = number
  default = 24
}

variable "vlan_id" {
  type    = number
  default = null
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "allow_scheduling_on_control_planes" {
  type        = bool
  default     = false
  description = "Run regular pods on control plane nodes (CP + worker)."
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "installer_image" {
  type        = string
  description = "From module.talos_image.installer_image."
}

variable "iso_ids" {
  type        = map(string)
  description = "Proxmox node => ISO file id, from module.talos_image.iso_ids."
}

variable "nodes" {
  description = "VM name => settings. Exactly one should be the endpoint controlplane."
  type = map(object({
    vm_id        = number
    ip           = string
    role         = string # "controlplane" or "worker"
    proxmox_node = string
    memory       = optional(number, 4096)
    cores        = optional(number, 2)
    disk_size    = optional(number, 20)
    # Second disk (scsi1 = /dev/sdb) for Longhorn, in GB. 0 = none.
    data_disk_size = optional(number, 0)
  }))

  validation {
    condition     = alltrue([for n in var.nodes : contains(["controlplane", "worker"], n.role)])
    error_message = "Each node role must be \"controlplane\" or \"worker\"."
  }
}
