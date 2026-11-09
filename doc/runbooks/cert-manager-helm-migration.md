# cert-manager: static manifest to Helm

One-time move of cert-manager on k8s-geese from the upstream static manifest
(`cert-manager.yaml` from the GitHub release, pulled by kustomize) to the
jetstack Helm chart (`infrastructure/cert-manager/helmrelease.yaml`).

Why: the manifest was downloaded from GitHub releases on every CI run and every
Flux reconcile, and those downloads sometimes time out (504). The chart comes
from charts.jetstack.io, fetched by Flux inside the cluster, like the other
Helm apps here.

## What actually happened (2026-11-09)

PR #60 was merged before step 1 (the `prune: disabled` annotation) was run.
Flux pruned the old objects within a minute of the merge, CRDs included, so
the `lab-wildcard` Certificate and both ClusterIssuers were deleted with them.
It recovered on its own:

- helm-controller installed the chart fresh (nothing left to adopt) and
  recreated the CRDs and the 3 Deployments.
- `cert-manager-config` re-applied the ClusterIssuers and `lab-wildcard`.
- The Secrets aren't owned by the Certificate or the issuers, so they stayed:
  `traefik/lab-wildcard-tls` (same cert, notBefore 2026-11-09 03:26 UTC) and
  the `letsencrypt-*-account` keys. The new Certificate picked up the existing
  Secret, so nothing was re-issued and Let's Encrypt wasn't contacted.
- Traefik kept serving the Secret the whole time, so `*.lab` HTTPS didn't
  drop. cert-manager itself was down for about a minute.

Lost: only the old Certificate/Issuer objects and their status history.

Lesson: when a PR needs a step on the cluster before merging, do that step
before pushing. Auto PR opens the PR on push, and it's easy to merge right
away. Or set `spec.suspend: true` on the Flux Kustomization in the same PR.

The rest of this page is the plan as written before the merge. It's still the
right way to do this kind of takeover next time.

## How the takeover works

The chart renders the same 46 objects as the manifest (same names, same
namespaces, same specs). Only the `cert-manager` Namespace isn't in the chart;
it's in `namespace.yaml` now.

- **kustomize-controller** would normally *delete* objects that leave the
  `cert-manager` Kustomization (`prune: true`). That includes the 6 CRDs, and
  deleting a CRD deletes every Certificate, Issuer and ClusterIssuer with it.
  Step 1 marks them `kustomize.toolkit.fluxcd.io/prune: disabled`, so Flux
  only drops them from its inventory.
- **helm-controller** then installs the release. It takes ownership of existing
  objects by default and uses server-side apply with forced conflicts, so it
  adopts them in place instead of failing with "already exists".
- `crds.keep: true` puts `helm.sh/resource-policy: keep` on the CRDs, so Helm
  never deletes them either, even on uninstall.
- `install.strategy: RetryOnFailure`: if the first install fails, it retries
  without uninstalling (the default would uninstall between attempts).

What changes on the cluster: Helm labels on every object, and
`--dns01-recursive-nameservers-only` becomes `...-only=true`. The pod labels
change too, so the 3 Deployments roll once. Certificates, their Secrets, the
issuers and the ACME account keys aren't touched. Checked on 2026-11-09 with
`kubectl diff --server-side --force-conflicts --field-manager=helm-controller`
against the rendered chart.

## Rollout (planned)

Before merging, from an up-to-date main (the old kustomization):

```sh
# 0. Note what must survive: CRD UIDs and the wildcard Secret UID
kubectl get crd -o custom-columns=NAME:.metadata.name,UID:.metadata.uid | grep cert-manager.io > /tmp/cm-before.txt
kubectl -n traefik get secret lab-wildcard-tls -o jsonpath='{.metadata.uid}{"\n"}' >> /tmp/cm-before.txt
cat /tmp/cm-before.txt

# 1. Tell Flux not to delete the old objects (should print "47 annotated")
kubectl kustomize kubernetes/infrastructure/cert-manager |
  kubectl annotate -f - --overwrite kustomize.toolkit.fluxcd.io/prune=disabled | wc -l
```

Then merge the PR, and reconcile instead of waiting up to an hour:

```sh
flux reconcile kustomization cert-manager --with-source
flux get helmrelease -n cert-manager cert-manager --watch   # until Ready / "Helm install succeeded"
```

## Checks

```sh
flux get kustomizations cert-manager cert-manager-config   # both Ready
helm -n cert-manager list                                   # cert-manager v1.21.2, deployed
kubectl -n cert-manager get deploy,pods                     # 3 Deployments 1/1, startupapicheck Completed

# Same UIDs as before = nothing was deleted and recreated
kubectl get crd -o custom-columns=NAME:.metadata.name,UID:.metadata.uid | grep cert-manager.io > /tmp/cm-after.txt
kubectl -n traefik get secret lab-wildcard-tls -o jsonpath='{.metadata.uid}{"\n"}' >> /tmp/cm-after.txt
diff /tmp/cm-before.txt /tmp/cm-after.txt && echo "same objects"

kubectl get clusterissuers                  # letsencrypt-prod/staging Ready
kubectl get certificate -A                  # lab-wildcard Ready
kubectl -n cert-manager get deploy cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}'   # has the DoH flags
kubectl -n cert-manager logs deploy/cert-manager | grep -i error | tail
```

Then open any `*.lab.felixlatulip.ca` app: the cert should still be the
Let's Encrypt wildcard.

Optional end-to-end test (webhook + DNS-01 over DoH), with the staging issuer:

```sh
kubectl -n traefik apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: cm-test }
spec:
  secretName: cm-test-tls
  dnsNames: [cm-test.lab.felixlatulip.ca]
  issuerRef: { kind: ClusterIssuer, name: letsencrypt-staging, group: cert-manager.io }
EOF
kubectl -n traefik wait certificate/cm-test --for=condition=Ready --timeout=10m
kubectl -n traefik delete certificate cm-test && kubectl -n traefik delete secret cm-test-tls
```

## If it goes wrong

- **HelmRelease not Ready:** `flux logs --kind=HelmRelease --name=cert-manager -n cert-manager`.
  The old objects are still running while it retries, so certs keep working.
- **Going back to the manifest:** suspend the release first. A suspended
  HelmRelease that gets deleted doesn't uninstall anything.

  ```sh
  flux suspend helmrelease -n cert-manager cert-manager
  git revert <merge commit> && git push      # Flux re-applies the manifest over the same objects
  flux reconcile kustomization cert-manager --with-source
  kubectl -n cert-manager delete secret -l owner=helm,name=cert-manager   # forget the Helm release
  ```

## Afterwards

If step 1 ran, the `prune: disabled` annotation stays on the objects. It's
harmless (Flux no longer manages them) and on the CRDs it's an extra safety
net, so leave it. (On 2026-11-09 it never ran, so the live objects don't have
it. The CRDs are still protected by `helm.sh/resource-policy: keep`.)
