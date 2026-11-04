# Rebuilding a cluster

Everything in a cluster comes back from git, except Longhorn data (restore it from the NAS backups) and the secrets below.

1. Create the VMs and Talos: `terraform -chdir=terraform apply`. To start over, first `terraform -chdir=terraform destroy -target=module.trusted` (new machine secrets, new etcd).
2. Write the kubeconfig and talosconfig (see [Health check](operations.md#health-check)).
3. k8s-trusted only: recreate the `sops-age` Secret (see [Secrets](secrets.md)).
4. Bootstrap Flux with a short-lived GitHub token (fine-grained, this repo only, Contents + Administration read/write). `flux-system/` is already in git, so bootstrap only adds a deploy key and doesn't push to `main`:

   ```sh
   export GITHUB_TOKEN=<token>
   flux bootstrap github --owner=folatulip --repository=homelab --personal \
     --branch=main --path=kubernetes/clusters/k8s-trusted   # or k8s-dmz
   ```

   Then delete the token. The deploy key stays.

## Turning on k8s-dmz

1. In UniFi: create VLAN 50 (`10.10.50.0/24`, gateway `10.10.50.1`, DHCP range clear of `.50`–`.51` and `.200`–`.220`) and tag it on the switch ports of both Proxmox hosts. Block DMZ → other VLANs in the firewall.
2. Set `dmz_enabled = true` in `terraform/main.tf` and apply. This also makes both host bridges carry VLAN 50 (`proxmox.tf`).
3. Bootstrap Flux with `--path=kubernetes/clusters/k8s-dmz` (step 4 above).

