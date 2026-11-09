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

## Creating k8s-geese

k8s-geese ([ADR 0001](adr/0001-single-cluster-cilium.md)) boots with no CNI, so Cilium has to go in before Flux can run.

1. In UniFi: check that `10.10.20.60`–`.61`, `10.10.50.60`–`.61` and `10.10.20.221`–`.240` are outside the DHCP ranges, and add the firewall rules from ADR section 8. **Do this first**: without them the DMZ node can't reach the API, and `apply` times out waiting for it.
2. `terraform -chdir=terraform apply`. Nodes stay `NotReady` until step 4.
3. Kubeconfig and talosconfig, merged next to the k8s-trusted ones (context `admin@k8s-geese`):

   ```sh
   terraform -chdir=terraform output -raw geese_kubeconfig > ~/.kube/k8s-geese.yaml
   KUBECONFIG=~/.kube/config:~/.kube/k8s-geese.yaml kubectl config view --flatten > ~/.kube/merged \
     && mv ~/.kube/merged ~/.kube/config && rm ~/.kube/k8s-geese.yaml
   terraform -chdir=terraform output -raw geese_talosconfig > /tmp/geese-talosconfig
   talosctl config merge /tmp/geese-talosconfig && rm /tmp/geese-talosconfig
   ```

4. Cilium: `scripts/bootstrap-cilium.sh admin@k8s-geese`. It waits until every node is `Ready`.
5. The `sops-age` Secret:

   ```sh
   kubectl --context admin@k8s-geese create namespace flux-system
   kubectl --context admin@k8s-geese -n flux-system create secret generic sops-age \
     --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
   ```

6. Flux, like step 4 above but with `--context=admin@k8s-geese --path=kubernetes/cluster`. `kubernetes/cluster/flux-system/` is in git, so nothing is pushed to `main`.
7. Check that Flux took over Cilium and that there's no kube-proxy:

   ```sh
   flux --context admin@k8s-geese get helmreleases -n kube-system   # cilium: Ready
   helm --kube-context admin@k8s-geese -n kube-system history cilium # last revision by helm-controller
   kubectl --context admin@k8s-geese -n kube-system get ds kube-proxy  # NotFound
   ```

8. In the Cloudflare tunnel's public hostnames, point `hello.felixlatulip.ca` at `traefik-dmz.traefik-dmz.svc.cluster.local`.

Then `curl https://hello.felixlatulip.ca` (DMZ) and `curl --resolve hello.lab.felixlatulip.ca:443:10.10.20.221 https://hello.lab.felixlatulip.ca` (trusted, once the wildcard cert is issued).
