variable "talos_version" {
  type        = string
  description = "Talos release, e.g. v1.14.4"
}

variable "proxmox_nodes" {
  type        = set(string)
  description = "Proxmox nodes that need the boot ISO (every node hosting a Talos VM)."
}

variable "extensions" {
  type        = list(string)
  default     = ["siderolabs/qemu-guest-agent"]
  description = "Official Talos system extensions baked into the image."
}
