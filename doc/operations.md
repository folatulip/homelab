# Day-to-day operations

## Health check

```sh
kubectl get nodes -L node-restriction.kubernetes.io/zone   # 4 Ready, 2 trusted + 2 dmz
talosctl -n 10.10.20.60 health
flux get kustomizations
cilium status   # or: kubectl -n kube-system get ds cilium
```

Contexts are `admin@k8s-geese` (kubectl, flux) and `k8s-geese` (talosctl). Kubeconfig and talosconfig come from Terraform:

```sh
terraform -chdir=terraform output -raw geese_kubeconfig > ~/.kube/config
terraform -chdir=terraform output -raw geese_talosconfig > ~/.talos/config
```

**Rebooting or resizing nodes:** see the end of [rebuild.md](rebuild.md#creating-k8s-geese). Changing a VM's RAM in Terraform shuts it down, and Talos cordons and drains it first. Changing both trusted nodes in one apply cordons both at once, so the LAN apps are down until they're back (~5 min). Change one at a time to avoid it.

## Deploying changes

Flux watches `main`. Merge a PR, and Flux applies the change within a minute.

```sh
flux reconcile kustomization flux-system --with-source   # apply now instead of waiting
flux get kustomizations                                  # status of each layer
```

Deleting a file from git deletes its objects from the cluster, because every Flux Kustomization has `prune: true`.

A few values are written as `${VAR}` in the manifests and set in `kubernetes/cluster/infrastructure.yaml` under `postBuild.substitute`, e.g. `TRAEFIK_IP` (`10.10.20.221`).

## Experiments

These are for trying things out. Anything managed by Flux gets reverted to what's in git on the next sync.

```sh
kubectl get pods -o wide                  # hello pods spread across cp1/w1
kubectl delete pod <one-of-them>          # watch a replacement appear
kubectl apply -f kubernetes/apps/trusted/pvc-test/ && kubectl logs pvc-test
kubectl delete -f kubernetes/apps/trusted/pvc-test/
```

To change the number of hello pods, edit `replicas` in `kubernetes/apps/trusted/hello/hello.yml` and push. Running `kubectl scale` would get reverted by Flux.
