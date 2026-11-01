# homelab

Two Kubernetes clusters running Talos Linux on a two-host Proxmox cluster (`geese`):

- **`k8s-trusted`**: LAN-only services, on VLAN 20.
- **`k8s-dmz`**: future public-facing apps, isolated on VLAN 50.

| Layer | Tool | Lives in |
|---|---|---|
| VMs and the Talos cluster | Terraform | `terraform/` |
| Everything running on the cluster | Kubernetes YAML, applied by Flux | `kubernetes/` |

## Nodes

Each cluster has one VM on each Proxmox host, so either host can go down for maintenance. The control planes also run workloads.

| Node | IP | Role | Host | RAM |
|---|---|---|---|---|
| k8s-trusted-cp1 | 10.10.20.50 | control plane + worker (API endpoint) | goose-s1-pve (`goose`) | 12 GB |
| k8s-trusted-w1 | 10.10.20.51 | worker | goose-s2-pve (`goose2`) | 6 GB |
| k8s-dmz-1 | 10.10.50.50 | control plane + worker (API endpoint) | goose-s1-pve (`goose`) | 4 GB |
| k8s-dmz-2 | 10.10.50.51 | worker | goose-s2-pve (`goose2`) | 3 GB |

The Proxmox node names are still `goose` and `goose2`; Terraform refers to them by those names.

`k8s-dmz` is off (`dmz_enabled = false` in `terraform/main.tf`) until VLAN 50 exists. See [Turning on k8s-dmz](#turning-on-k8s-dmz).

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

## Layout

```
kubernetes/
  clusters/
    k8s-trusted/           Flux entry point for k8s-trusted
      flux-system/         Flux itself (written by flux bootstrap)
      infrastructure.yaml  which add-ons to apply, in what order, with this cluster's IPs
      apps.yaml            applies kubernetes/apps/ after ingress + storage are ready
    k8s-dmz/               Flux entry point for k8s-dmz (base add-ons only, no apps yet)
  infrastructure/          add-ons, shared by both clusters
    metallb/               load balancer controller
    metallb-config/        IP pool, set per cluster (L2 mode)
    traefik/               ingress controller, fixed IP set per cluster
    local-path-provisioner/ StorageClass "local-path" (node-local scratch)
    longhorn/              default StorageClass "longhorn" (replicated), trusted only
    longhorn-config/       backup schedule to the NAS, trusted only
    cert-manager/          issues TLS certificates, trusted only
    cert-manager-config/   Let's Encrypt issuers, Cloudflare token, *.lab wildcard cert
  apps/                    k8s-trusted apps
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

CI runs on the push. Once the 6 checks pass, merge the PR. Flux then deploys from `main` to both clusters.

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org): `<type>(<scope>): <description>`, with a header of 72 chars max and a lowercase scope.

| Type | For |
|---|---|
| `feat` | something new: an app, an add-on, a capability |
| `fix` | fixing something broken |
| `chore` | upkeep, dependency bumps (Renovate uses `chore(deps)`) |
| `refactor` | same result, restructured |
| `docs` / `ci` / `build` / `test` / `perf` / `style` / `revert` | what they say |

Typical scopes: `terraform`, `talos`, `flux`, `metallb`, `traefik`, `storage`, `apps`, `dmz`, `ci`. Add `!` for breaking changes, e.g. `fix(talos)!: …`.

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

Both clusters use the same folders under `kubernetes/infrastructure/`. Values that differ per cluster are written as `${VAR}` in the manifest and set in that cluster's `infrastructure.yaml` under `postBuild.substitute`:

| Variable | k8s-trusted | k8s-dmz |
|---|---|---|
| `LB_RANGE` (MetalLB pool) | 10.10.20.200-10.10.20.220 | 10.10.50.200-10.10.50.220 |
| `TRAEFIK_IP` | 10.10.20.201 | 10.10.50.201 |

### Adding an app

1. Create `kubernetes/apps/<name>/` with the manifests and a `kustomization.yaml`. Copy `hello/` as a starting point.
2. Add `<name>` to `kubernetes/apps/kustomization.yaml`.
3. To reach it from the LAN, add an `Ingress`. Traefik is the default ingress class, so no `ingressClassName` is needed.
4. Commit and push.

## Networking

- **VLANs:** k8s-trusted on VLAN 20 (`10.10.20.0/24`, untagged on `vmbr0`). k8s-dmz on VLAN 50 (`10.10.50.0/24`); its VMs tag their own traffic, so both host bridges must be VLAN-aware and carry 50.
- **LoadBalancer IPs:** MetalLB hands out `10.10.20.200`–`10.10.20.220` (trusted) and `10.10.50.200`–`10.10.50.220` (DMZ).
- **Ingress:** Traefik is at `10.10.20.201` (trusted) and `10.10.50.201` (DMZ), on ports 80 and 443. On 443 the trusted one serves the `*.lab.felixlatulip.ca` wildcard cert (see [Certificates](#certificates)).
- **Hostnames:** `<app>.lab.felixlatulip.ca`, e.g. https://hello.lab.felixlatulip.ca. Until DNS points there, use `<app>.10.10.20.201.sslip.io` over HTTP.
- **Traefik dashboard:** `kubectl -n traefik port-forward deploy/traefik 8080`, then http://localhost:8080/dashboard/

## Storage

**`longhorn`** (k8s-trusted only) is the default StorageClass. Each volume is kept on both nodes (2 replicas), one per Proxmox host, so if one goes down its pods can restart on the other with their data.

- Data lives on a dedicated 50 GB disk per node (`data_disk_size` in `terraform/main.tf`), mounted by Talos at `/var/mnt/longhorn` (`patches/data-disk/longhorn-volume.yaml`, applied to nodes with a data disk). With 2 replicas, usable space is about one disk.
- Talos needs the `iscsi-tools` and `util-linux-tools` extensions for Longhorn; they're in the image list in `terraform/main.tf`.
- UI (no login, so it isn't exposed): `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8000:80`, then http://localhost:8000

**Backups** go to the Unraid NAS over NFS: `nfs://10.10.20.3:/mnt/user/longhorn`. Every volume is backed up daily (7 kept) and weekly on Sundays (4 kept), from `longhorn-config/recurring-jobs.yaml`. Backups are incremental and survive deleting the volume or the whole cluster. To restore: Longhorn UI → Backup → pick a backup → Restore, then point a PVC at the restored volume.

**`local-path`** is there for scratch data on k8s-trusted, and is the only storage on k8s-dmz: set `storageClassName: local-path`. Its volumes are directories under `/var/mnt/local-path-provisioner` on one node's system disk, aren't replicated or backed up, and share the ~19 GB EPHEMERAL partition with images and logs.

## Certificates

k8s-trusted is LAN-only, but its certs are real Let's Encrypt ones, trusted by every device with no setup. cert-manager gets them with a **DNS-01** challenge: it proves ownership of `felixlatulip.ca` by writing a TXT record through the Cloudflare API, so nothing has to be reachable from the internet.

- **One wildcard cert** for `*.lab.felixlatulip.ca`, Traefik's default certificate. It's in `infrastructure/cert-manager-config/wildcard.yaml`. Any Ingress host under `lab.felixlatulip.ca` gets valid HTTPS on 443 without a `tls` section. App names stay out of public Certificate Transparency logs; only the wildcard appears there.
- **Issuers:** `letsencrypt-prod` for real certs, and `letsencrypt-staging` for testing changes (untrusted certs, higher rate limits).
- **Renewal** is automatic, about 30 days before the 90-day expiry. Check status with `kubectl get certificates -A`.
- **Cloudflare token** lives in `cert-manager-config/cloudflare-api-token.sops.yaml`. It's scoped to Zone:DNS:Edit and Zone:Zone:Read on `felixlatulip.ca` only. Rotate it with `sops <file>`.

**DNS for app names.** Point `*.lab.felixlatulip.ca` at Traefik (`10.10.20.201`) in one of two ways:
- a local DNS record on the UniFi gateway: LAN-only, preferred
- a DNS-only (grey cloud) record in Cloudflare: works everywhere, but publishes the private IP

Until then, the `sslip.io` hostnames work over plain HTTP.

## Secrets

Secrets (k8s-trusted only) are committed encrypted with [sops](https://github.com/getsops/sops) + [age](https://age-encryption.org), and Flux decrypts them in the cluster. Any file named `*.sops.yaml` under `kubernetes/` is encrypted with the public key in `.sops.yaml`. Only `data`/`stringData` values get encrypted, so names and keys stay readable.

```sh
sops -e -i kubernetes/apps/<app>/secret.sops.yaml   # encrypt a new Secret before committing
sops kubernetes/apps/<app>/secret.sops.yaml         # edit in $EDITOR (decrypts, re-encrypts on save)
sops -d kubernetes/apps/<app>/secret.sops.yaml      # print decrypted
```

Then list the file in the app's `kustomization.yaml` like any other manifest. `hello/secret.sops.yaml` is an example. CI fails if a `*.sops.yaml` file is committed unencrypted.

k8s-dmz doesn't get the age key and its Kustomizations have no decryption, so a compromised DMZ cluster can't read trusted secrets. It will get its own key when it needs secrets.

**The private key** is in `~/Library/Application Support/sops/age/keys.txt` on the Mac, and in the cluster as Secret `flux-system/sops-age`. It isn't in git. Keep a copy in a password manager. Without it, nothing encrypted can be decrypted. After rebuilding the cluster, recreate the Secret before Flux syncs:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

## Talos 1.14 notes

- Kubelet settings live in the `KubeletConfig` document. Patching `.machine.kubelet` fails with `kubelet config is already set in v1alpha1 config`, and `extraMounts` no longer exists. Host paths for pods go under `/var/mnt` as user volumes.
- Install settings live in `UnattendedInstallConfig`, not `.machine.install`.
- A control plane that runs workloads needs `cluster.allowSchedulingOnControlPlanes: true`; the talos-cluster module adds it when `allow_scheduling_on_control_planes = true`.
- Talos enforces the `baseline` Pod Security level. Namespaces whose pods need host access (`metallb-system`, `local-path-storage`, `longhorn-system`) are labeled `pod-security.kubernetes.io/enforce: privileged`.
- System extensions are baked into the image. Changing the `extensions` list in `terraform/main.tf` changes the installer image; after `terraform apply`, roll each node with `talosctl -n <ip> upgrade --image "$(terraform -chdir=terraform output -raw installer_image)"`.
- Check a config patch before applying it: `talosctl validate --config <file> --mode metal`.

## Rebuilding a cluster

Everything in a cluster comes back from git, except Longhorn data (restore it from the NAS backups) and the secrets below.

1. Create the VMs and Talos: `terraform -chdir=terraform apply`. To start over, first `terraform -chdir=terraform destroy -target=module.trusted` (new machine secrets, new etcd).
2. Write the kubeconfig and talosconfig (see [Health check](#health-check)).
3. k8s-trusted only: recreate the `sops-age` Secret (see [Secrets](#secrets)).
4. Bootstrap Flux with a short-lived GitHub token (fine-grained, this repo only, Contents + Administration read/write). `flux-system/` is already in git, so bootstrap only adds a deploy key and doesn't push to `main`:

   ```sh
   export GITHUB_TOKEN=<token>
   flux bootstrap github --owner=VypperFO --repository=homelab --personal \
     --branch=main --path=kubernetes/clusters/k8s-trusted   # or k8s-dmz
   ```

   Then delete the token. The deploy key stays.

### Turning on k8s-dmz

1. In UniFi: create VLAN 50 (`10.10.50.0/24`, gateway `10.10.50.1`, DHCP range clear of `.50`–`.51` and `.200`–`.220`) and tag it on the switch ports of both Proxmox hosts. Block DMZ → other VLANs in the firewall.
2. Set `dmz_enabled = true` in `terraform/main.tf` and apply. This also makes both host bridges carry VLAN 50 (`proxmox.tf`).
3. Bootstrap Flux with `--path=kubernetes/clusters/k8s-dmz` (step 4 above).

## Experiments

These are for trying things out. Anything managed by Flux gets reverted to what's in git on the next sync.

```sh
kubectl get pods -o wide                  # hello pods spread across cp1/w1
kubectl delete pod <one-of-them>          # watch a replacement appear
kubectl apply -f kubernetes/apps/pvc-test/ && kubectl logs pvc-test
kubectl delete -f kubernetes/apps/pvc-test/
```

To change the number of hello pods, edit `replicas` in `kubernetes/apps/hello/hello.yml` and push. Running `kubectl scale` would get reverted by Flux.
