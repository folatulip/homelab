# Secrets (sops + age)

Secrets are committed encrypted with [sops](https://github.com/getsops/sops) + [age](https://age-encryption.org), and Flux decrypts them in the cluster. Any file named `*.sops.yaml` under `kubernetes/` is encrypted with the public key in `.sops.yaml`. Only `data`/`stringData` values get encrypted, so names and keys stay readable.

```sh
sops -e -i kubernetes/apps/trusted/<app>/secret.sops.yaml   # encrypt a new Secret before committing
sops kubernetes/apps/trusted/<app>/secret.sops.yaml         # edit in $EDITOR (decrypts, re-encrypts on save)
sops -d kubernetes/apps/trusted/<app>/secret.sops.yaml      # print decrypted
```

Then list the file in the app's `kustomization.yaml` like any other manifest. `hello/secret.sops.yaml` is an example. CI fails if a `*.sops.yaml` file is committed unencrypted.

There's **one age key** for every secret, DMZ ones included ([ADR 0001](adr/0001-single-cluster-cilium.md), section 7). k8s-dmz used to have its own key; it was retired with that cluster, and old commits encrypted to it can only be read with a key that no longer exists.

**The private key** is in `~/Library/Application Support/sops/age/keys.txt` on the Mac, and in the cluster as Secret `flux-system/sops-age`. It isn't in git. Keep a copy in a password manager. Without it, nothing encrypted can be decrypted. After rebuilding the cluster, recreate the Secret before Flux syncs:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

