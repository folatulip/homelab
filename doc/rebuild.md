# Rebuilding a cluster

Everything in a cluster comes back from git, except Longhorn data (restore it from the NAS backups) and the secrets below.

1. Create the VMs and Talos: `terraform -chdir=terraform apply`. To start over, first `terraform -chdir=terraform destroy -target=module.geese` (new machine secrets, new etcd).
2. Write the kubeconfig and talosconfig (see [Health check](operations.md#health-check)).
3. Recreate the `sops-age` Secret (see [Secrets](secrets.md)).
4. Cilium, then Flux: see [Creating k8s-geese](#creating-k8s-geese) below (steps 4 to 7).

VLAN 50 (`10.10.50.0/24`, gateway `10.10.50.1`) stays in UniFi and on both host bridges (`proxmox.tf`): k8s-geese's DMZ nodes use it ([ADR 0001](adr/0001-single-cluster-cilium.md)).

## Creating k8s-geese

k8s-geese ([ADR 0001](adr/0001-single-cluster-cilium.md)) boots with no CNI, so Cilium has to go in before Flux can run.

1. In UniFi: check that `10.10.20.60`–`.61`, `10.10.50.60`–`.61` and `10.10.20.221`–`.240` are outside the DHCP ranges, and add the firewall rules from ADR section 8. **Do this first**: without them the DMZ node can't reach the API, and `apply` times out waiting for it. VLAN 50 is in the **DMZ** zone, so the DMZ → trusted policies need Src. Zone = DMZ (not Internal), or they never match. If dmz1 doesn't register, its console says `waiting for apid` and cp1's `trustd` log has no request from `10.10.50.x`.
2. `terraform -chdir=terraform apply`. Nodes stay `NotReady` until step 4.
3. Kubeconfig and talosconfig, merged into your local config (context `admin@k8s-geese`):

   ```sh
   terraform -chdir=terraform output -raw geese_kubeconfig > ~/.kube/k8s-geese.yaml
   KUBECONFIG=~/.kube/config:~/.kube/k8s-geese.yaml kubectl config view --flatten > ~/.kube/merged \
     && mv ~/.kube/merged ~/.kube/config && rm ~/.kube/k8s-geese.yaml
   terraform -chdir=terraform output -raw geese_talosconfig > /tmp/geese-talosconfig
   talosctl config merge /tmp/geese-talosconfig && rm /tmp/geese-talosconfig
   ```

4. Cilium: `scripts/bootstrap-cilium.sh admin@k8s-geese`. It waits until every node is `Ready`.
5. The `sops-age` Secret (`keys.txt` only has the trusted key now):

   ```sh
   kubectl --context admin@k8s-geese create namespace flux-system
   kubectl --context admin@k8s-geese -n flux-system create secret generic sops-age \
     --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
   ```

6. Flux. Installed by hand instead of `flux bootstrap github`: it's what bootstrap does (manifests from git, an SSH key, a read-only deploy key), but it never pushes to `main` and needs no GitHub token. Delete the old `./kubernetes/cluster` deploy key on GitHub first if there is one.

   ```sh
   k="--context=admin@k8s-geese"
   kubectl $k apply --server-side -f kubernetes/cluster/flux-system/gotk-components.yaml
   kubectl $k -n flux-system wait --for=condition=Available deploy --all --timeout=5m
   flux $k create secret git flux-system -n flux-system \
     --url=ssh://git@github.com/folatulip/homelab --ssh-key-algorithm=ecdsa --ssh-ecdsa-curve=p384
   kubectl $k -n flux-system get secret flux-system -o jsonpath='{.data.identity\.pub}' | base64 -d > /tmp/geese.pub
   gh repo deploy-key add /tmp/geese.pub --repo folatulip/homelab \
     --title "flux-system-main-flux-system-./kubernetes/cluster" && rm /tmp/geese.pub   # read-only by default
   kubectl $k apply --server-side -k kubernetes/cluster/flux-system
   flux $k get kustomizations --watch    # ~5 min until all Ready
   ```

7. Check that Flux took over Cilium (it did the first time: `cilium.v2`, upgraded by helm-controller) and that there's no kube-proxy:

   ```sh
   flux --context admin@k8s-geese get helmreleases -n kube-system   # cilium: Ready
   helm --kube-context admin@k8s-geese -n kube-system history cilium # last revision by helm-controller
   kubectl --context admin@k8s-geese -n kube-system get ds kube-proxy  # NotFound
   ```

8. In the Cloudflare tunnel's public hostnames, point `hello.felixlatulip.ca` at `traefik-dmz.traefik-dmz.svc.cluster.local`.

**Rebooting a node:** `kubectl drain` it first (`--ignore-daemonsets --delete-emptydir-data`), then `talosctl -n <ip> reboot`, then `kubectl uncordon`. Without the drain, the scheduler keeps putting new pods on the node while it shuts down, and it rejects each one (`NodeShutdown`): ~90 dead `cilium-operator` pods in 2 minutes. Clean up with `kubectl delete pods -A --field-selector=status.phase=Failed`.

Then `curl https://hello.felixlatulip.ca` (DMZ) and `curl --resolve hello.lab.felixlatulip.ca:443:10.10.20.221 https://hello.lab.felixlatulip.ca` (trusted, once the wildcard cert is issued).
