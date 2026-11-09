# Adding an app

Apps are Helm charts deployed by Flux. A `HelmRepository` says where the chart lives. A `HelmRelease` says which version to install and with what values.

- Template: [`templates/helm-app/`](templates/helm-app/)
- Real example: [`kubernetes/apps/trusted/vaultwarden/`](../kubernetes/apps/trusted/vaultwarden/)
- No chart for the app? Use [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) (`oci://ghcr.io/bjw-s-labs/helm`, chart `app-template`).

## 1. Copy the template

```sh
app=myapp
cp -r doc/templates/helm-app kubernetes/apps/trusted/$app
sed -i '' "s/APP_NAME/$app/g" kubernetes/apps/trusted/$app/*.yaml   # GNU sed: drop the ''
```

Then replace the chart placeholders:

| Placeholder | Example (Vaultwarden) |
|---|---|
| `REPO_NAME` | `helmforge` |
| `REPO_URL` | `oci://ghcr.io/helmforgedev/helm` |
| `CHART_NAME` | `vaultwarden` |
| `CHART_VERSION` | `1.14.6` |

Pin an exact version. Renovate opens PRs for new ones.

## 2. Set the values

```sh
helm show values oci://ghcr.io/helmforgedev/helm/vaultwarden --version 1.14.6
```

Copy only what you change into `values:` in `helmrelease.yaml`. Key names for ingress, secrets and PVCs differ between charts.

For a classic `https://` repo, remove `type: oci` from `helmrepository.yaml`.

## 3. Storage

`pvcs.yaml` uses `longhorn-retain`: backed up to the NAS, kept if the PVC is deleted. Point the chart at it, often with `persistence.existingClaim`.

No data? Delete `pvcs.yaml` and its line in `kustomization.yaml`.

## 4. Secrets

Put the real values in `secret.sops.yaml`, then encrypt before committing:

```sh
sops -e -i kubernetes/apps/trusted/$app/secret.sops.yaml
```

CI fails on an unencrypted `*.sops.yaml`. No secret? Delete the file and its line.

## 5. Ingress

Use `<app>.lab.felixlatulip.ca`. Traefik is the default class and serves the `*.lab` wildcard cert, so no `ingressClassName` or `tls` is needed.

## 6. Check and enable

```sh
kubectl kustomize kubernetes/apps/trusted/$app
scripts/ci/validate-kubernetes.sh    # same as CI, needs kubeconform
```

Add `$app` to `kubernetes/apps/trusted/kustomization.yaml`. Unlisted folders are ignored.

## 7. Ship

Commit as `feat(apps): add <app>`, push, merge once CI is green.

```sh
flux get helmreleases -n $app
kubectl -n $app get pods,ingress
```

Public apps go in `kubernetes/apps/dmz/` and need a tunnel hostname. See [networking.md](networking.md#public-apps-dmz).
