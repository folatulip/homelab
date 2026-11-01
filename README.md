# homelab

Kubernetes cluster `geese-k8s` running Talos Linux on Proxmox.

| Layer | Tool | Lives in |
|---|---|---|
| VMs and the Talos cluster | Terraform | `terraform/` |
| Everything running on the cluster | Kubernetes YAML, applied by Flux | `kubernetes/` |

## Nodes

| Node | IP | Role |
|---|---|---|
| talos-cp1 | 10.10.20.50 | control plane (API endpoint) |
| talos-w1 | 10.10.20.75 | worker |
| talos-w2 | 10.10.20.62 | worker |

## Health check

```sh
kubectl get nodes -o wide
talosctl -n 10.10.20.50 health
flux get kustomizations
```

## Layout

```
kubernetes/
  clusters/geese-k8s/      Flux entry point (bootstrap writes flux-system/ here)
    infrastructure.yaml    which add-ons to apply, and in what order
    apps.yaml              applies kubernetes/apps/ after ingress + storage are ready
  infrastructure/
    metallb/               load balancer controller
    metallb-config/        IP pool 10.10.20.200-220 (L2 mode)
    traefik/               ingress controller, fixed IP 10.10.20.201
    local-path-provisioner/ default StorageClass "local-path"
    cert-manager/          issues TLS certificates
    cert-manager-config/   Let's Encrypt issuers, Cloudflare token, *.lab wildcard cert
  apps/
    kustomization.yaml     list of apps Flux deploys
    hello/                 example app
    pvc-test/              throwaway storage check (not deployed by Flux)
```

## Workflow

`main` is protected, so every change goes through a PR:

```sh
git switch -c feat/vaultwarden
git commit -m "feat(apps): add vaultwarden"
git push -u origin HEAD        # the Auto PR workflow opens the PR
```

CI runs on the push. Once the 5 checks pass, merge the PR. Flux then deploys from `main`.

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org): `<type>(<scope>): <description>`, with a header of 72 chars max and a lowercase scope.

| Type | For |
|---|---|
| `feat` | something new: an app, an add-on, a capability |
| `fix` | fixing something broken |
| `chore` | upkeep, dependency bumps (Renovate uses `chore(deps)`) |
| `refactor` | same result, restructured |
| `docs` / `ci` / `build` / `test` / `perf` / `style` / `revert` | what they say |

Typical scopes: `terraform`, `talos`, `flux`, `metallb`, `traefik`, `storage`, `apps`, `ci`. Add `!` for breaking changes, e.g. `fix(talos)!: …`.

The **Commit messages** CI job checks every commit on the branch. To get the same check at commit time, enable the local hook once per clone:

```sh
git config core.hooksPath scripts/git-hooks
```

## Deploying changes

Flux watches `main`. Merge a PR, and Flux applies the change within a minute.

```sh
flux reconcile kustomization flux-system --with-source   # apply now instead of waiting
flux get kustomizations                                  # status of each layer
```

Deleting a file from git deletes its objects from the cluster, because every Flux Kustomization has `prune: true`.

### Adding an app

1. Create `kubernetes/apps/<name>/` with the manifests and a `kustomization.yaml`. Copy `hello/` as a starting point.
2. Add `<name>` to `kubernetes/apps/kustomization.yaml`.
3. To reach it from the LAN, add an `Ingress`. Traefik is the default ingress class, so no `ingressClassName` is needed.
4. Commit and push.

## Networking

- **LoadBalancer IPs:** MetalLB hands out `10.10.20.200`–`10.10.20.220` on VLAN 20.
- **Ingress:** Traefik is at `10.10.20.201`, on ports 80 and 443. On 443 it serves the `*.lab.felixlatulip.ca` wildcard cert (see [Certificates](#certificates)).
- **Hostnames:** `<app>.lab.felixlatulip.ca`, e.g. https://hello.lab.felixlatulip.ca. Until DNS points there, use `<app>.10.10.20.201.sslip.io` over HTTP.
- **Traefik dashboard:** `kubectl -n traefik port-forward deploy/traefik 8080`, then http://localhost:8080/dashboard/

## Storage

`local-path` is the default StorageClass. Volumes are directories under `/var/mnt/local-path-provisioner` on the worker's system disk. Terraform creates that directory as a Talos `UserVolumeConfig` (`terraform/modules/talos-cluster/talos.tf`).

- A volume is tied to the node it was created on. If that node is down, pods using it can't start elsewhere.
- Volumes share the ~19 GB EPHEMERAL partition with container images and logs.

## Certificates

This cluster is LAN-only, but its certs are real Let's Encrypt ones, trusted by every device with no setup. cert-manager gets them with a **DNS-01** challenge: it proves ownership of `felixlatulip.ca` by writing a TXT record through the Cloudflare API, so nothing has to be reachable from the internet.

- **One wildcard cert** for `*.lab.felixlatulip.ca`, Traefik's default certificate. It's in `infrastructure/cert-manager-config/wildcard.yaml`. Any Ingress host under `lab.felixlatulip.ca` gets valid HTTPS on 443 without a `tls` section. App names stay out of public Certificate Transparency logs; only the wildcard appears there.
- **Issuers:** `letsencrypt-prod` for real certs, and `letsencrypt-staging` for testing changes (untrusted certs, higher rate limits).
- **Renewal** is automatic, about 30 days before the 90-day expiry. Check status with `kubectl get certificates -A`.
- **Cloudflare token** lives in `cert-manager-config/cloudflare-api-token.sops.yaml`. It's scoped to Zone:DNS:Edit and Zone:Zone:Read on `felixlatulip.ca` only. Rotate it with `sops <file>`.

**DNS for app names.** Point `*.lab.felixlatulip.ca` at Traefik (`10.10.20.201`) in one of two ways:
- a local DNS record on the UniFi gateway: LAN-only, preferred
- a DNS-only (grey cloud) record in Cloudflare: works everywhere, but publishes the private IP

Until then, the `sslip.io` hostnames work over plain HTTP.

## Secrets

Secrets are committed encrypted with [sops](https://github.com/getsops/sops) + [age](https://age-encryption.org), and Flux decrypts them in the cluster. Any file named `*.sops.yaml` under `kubernetes/` is encrypted with the public key in `.sops.yaml`. Only `data`/`stringData` values get encrypted, so names and keys stay readable.

```sh
sops -e -i kubernetes/apps/<app>/secret.sops.yaml   # encrypt a new Secret before committing
sops kubernetes/apps/<app>/secret.sops.yaml         # edit in $EDITOR (decrypts, re-encrypts on save)
sops -d kubernetes/apps/<app>/secret.sops.yaml      # print decrypted
```

Then list the file in the app's `kustomization.yaml` like any other manifest. `hello/secret.sops.yaml` is an example. CI fails if a `*.sops.yaml` file is committed unencrypted.

**The private key** is in `~/Library/Application Support/sops/age/keys.txt` on the Mac, and in the cluster as Secret `flux-system/sops-age`. It isn't in git. Keep a copy in a password manager. Without it, nothing encrypted can be decrypted. After rebuilding the cluster, recreate the Secret before Flux syncs:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

## Talos 1.14 notes

- Kubelet settings live in the `KubeletConfig` document. Patching `.machine.kubelet` fails with `kubelet config is already set in v1alpha1 config`, and `extraMounts` no longer exists. Host paths for pods go under `/var/mnt` as user volumes.
- Install settings live in `UnattendedInstallConfig`, not `.machine.install`.
- Talos enforces the `baseline` Pod Security level. Namespaces whose pods need host access (`metallb-system`, `local-path-storage`) are labeled `pod-security.kubernetes.io/enforce: privileged`.
- Check a config patch before applying it: `talosctl validate --config <file> --mode metal`.

## Experiments

These are for trying things out. Anything managed by Flux gets reverted to what's in git on the next sync.

```sh
kubectl get pods -o wide                  # hello pods spread across w1/w2
kubectl delete pod <one-of-them>          # watch a replacement appear
kubectl apply -f kubernetes/apps/pvc-test/ && kubectl logs pvc-test
kubectl delete -f kubernetes/apps/pvc-test/
```

To change the number of hello pods, edit `replicas` in `kubernetes/apps/hello/hello.yml` and push. Running `kubectl scale` would get reverted by Flux.
