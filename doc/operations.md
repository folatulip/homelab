# Day-to-day operations

## Health check

```sh
kubectl get nodes -o wide
talosctl -n 10.10.20.50 health      # k8s-dmz: -n 10.10.50.50
flux get kustomizations
```

Kubeconfig and talosconfig come from Terraform:

```sh
terraform -chdir=terraform output -raw trusted_kubeconfig > ~/.kube/config
terraform -chdir=terraform output -raw trusted_talosconfig > ~/.talos/config
# k8s-dmz: dmz_kubeconfig / dmz_talosconfig
```

## Deploying changes

Flux watches `main`. Merge a PR, and Flux applies the change within a minute.

```sh
flux reconcile kustomization flux-system --with-source   # apply now instead of waiting
flux get kustomizations                                  # status of each layer
```

Deleting a file from git deletes its objects from the cluster, because every Flux Kustomization has `prune: true`.

Both clusters use the same folders under `kubernetes/infrastructure/`. Values that differ per cluster are written as `${VAR}` in the manifest and set in that cluster's `infrastructure.yaml` under `postBuild.substitute`:

| Variable | k8s-trusted | k8s-dmz |
|---|---|---|
| `LB_RANGE` (MetalLB pool) | 10.10.20.200-10.10.20.220 | 10.10.50.200-10.10.50.220 |
| `TRAEFIK_IP` | 10.10.20.201 | 10.10.50.201 |

## Experiments

These are for trying things out. Anything managed by Flux gets reverted to what's in git on the next sync.

```sh
kubectl get pods -o wide                  # hello pods spread across cp1/w1
kubectl delete pod <one-of-them>          # watch a replacement appear
kubectl apply -f kubernetes/apps/pvc-test/ && kubectl logs pvc-test
kubectl delete -f kubernetes/apps/pvc-test/
```

To change the number of hello pods, edit `replicas` in `kubernetes/apps/hello/hello.yml` and push. Running `kubectl scale` would get reverted by Flux.
