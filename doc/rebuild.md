# Rebuilding a cluster

Everything in a cluster comes back from git, except Longhorn data (restore it from the NAS backups) and the secrets below.

1. Create the VMs and Talos: `terraform -chdir=terraform apply`. To start over, first `terraform -chdir=terraform destroy -target=module.trusted` (new machine secrets, new etcd).
2. Write the kubeconfig and talosconfig (see [Health check](operations.md#health-check)).
3. Recreate the `sops-age` Secret (see [Secrets](secrets.md)).
4. Bootstrap Flux with a short-lived GitHub token (fine-grained, this repo only, Contents + Administration read/write). `flux-system/` is already in git, so bootstrap only adds a deploy key and doesn't push to `main`:

   ```sh
   export GITHUB_TOKEN=<token>
   flux bootstrap github --owner=folatulip --repository=homelab --personal \
     --branch=main --path=kubernetes/clusters/k8s-trusted
   ```

   Then delete the token. The deploy key stays.

VLAN 50 (`10.10.50.0/24`, gateway `10.10.50.1`) stays in UniFi and on both host bridges (`proxmox.tf`): k8s-geese's DMZ nodes use it ([ADR 0001](adr/0001-single-cluster-cilium.md)).

