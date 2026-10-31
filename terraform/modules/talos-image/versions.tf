# Minimum versions only; the root module (terraform/versions.tf) pins exact ones.
terraform {
  required_version = ">= 1.9"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.118.0"
    }
    talos = {
      source  = "siderolabs/talos"
      version = ">= 0.12.0"
    }
  }
}
