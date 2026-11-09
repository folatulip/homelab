# =====================================================================
# Proxmox cluster "geese": host-level settings. Edit this file.
# =====================================================================
#
# !! Changing a node's `ip` is NOT just a Terraform edit: corosync and
# !! /etc/hosts still point at the old IP, so the cluster loses quorum.
# !! Change IPs by hand (pvecm docs), then update the value here.

module "proxmox" {
  source = "./modules/proxmox-base"

  timezone = "America/Toronto"

  # Default DNS for every node.
  dns = {
    domain  = "pve"
    servers = ["1.1.1.1", "1.0.0.1"]
  }

  nodes = {
    goose = {
      ip           = "10.10.20.2"
      gateway      = "10.10.20.1"
      bridge_ports = ["eno1"]
      vlan_aware   = true
      vlans        = local.dmz_enabled ? [20, 50] : [20] # 50 = DMZ (main.tf)
    }

    goose2 = {
      ip           = "10.10.20.4"
      gateway      = "10.10.20.1"
      bridge_ports = ["nic0"]
      vlan_aware   = local.dmz_enabled # carries VLAN 50 for k8s-dmz-2
      vlans        = [20, 50]

      # The hosts don't need an IP on VLAN 50: VMs tag their own traffic.
    }
  }

  # NAS shares. Passwords go in terraform.tfvars:
  nas_storages = {
    goose-nas-data = {
      type     = "cifs"
      server   = "10.10.20.3"
      share    = "data"
      username = "proxmox-data"
      content  = ["images"]
      # Files owned by uid/gid 100000 = root inside unprivileged LXCs
      options = "uid=100000,gid=100000,file_mode=0775,dir_mode=0775"
    }
    goose-nas-cloud = {
      type     = "cifs"
      server   = "10.10.20.3"
      share    = "cloud"
      username = "proxmox-cloud"
      content  = ["images"]
    }
    goose-nas-photos = {
      type     = "cifs"
      server   = "10.10.20.3"
      share    = "photos"
      username = "proxmox-photos"
      content  = ["images"]
    }
    # goose-nas-backup = {
    #  type     = "cifs"
    #  server   = "10.10.20.10"
    #  share    = "proxmox"
    #  username = "proxmox"
    #  content  = ["backup", "iso", "vztmpl"]
    #  backups  = { keep_daily = 7, keep_weekly = 4, keep_monthly = 3 }
    # }
  }
  nas_passwords = var.nas_passwords
}

# goose-nas-cloud was created in the Proxmox UI before it was added here.
# The API never returns SMB passwords, so the import has none and the plan
# replaces it once to set the password from terraform.tfvars. Deleting a
# storage only removes its config in Proxmox, the files on the NAS stay.
# Can be removed once it's imported (terraform apply).
import {
  to = module.proxmox.proxmox_storage_cifs.this["goose-nas-cloud"]
  id = "goose-nas-cloud"
}
