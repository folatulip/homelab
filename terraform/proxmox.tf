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
      vlans        = [20]
    }

    goose2 = {
      ip           = "10.10.20.4"
      gateway      = "10.10.20.1"
      bridge_ports = ["nic0"]
      vlan_aware   = false # set true + vlans = [20, 30] before the DMZ cluster (VLAN 30)

      # Example: give the host an IP on VLAN 30.
      # vlan_interfaces = {
      #   dmz = { vlan = 30, address = "10.10.30.4/24", comment = "DMZ" }
      # }
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
