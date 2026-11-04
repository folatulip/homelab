# Secrets (sops + age)

Secrets (k8s-trusted only) are committed encrypted with [sops](https://github.com/getsops/sops) + [age](https://age-encryption.org), and Flux decrypts them in the cluster. Any file named `*.sops.yaml` under `kubernetes/` is encrypted with the public key in `.sops.yaml`. Only `data`/`stringData` values get encrypted, so names and keys stay readable.

```sh
sops -e -i kubernetes/apps/<app>/secret.sops.yaml   # encrypt a new Secret before committing
sops kubernetes/apps/<app>/secret.sops.yaml         # edit in $EDITOR (decrypts, re-encrypts on save)
sops -d kubernetes/apps/<app>/secret.sops.yaml      # print decrypted
```

Then list the file in the app's `kustomization.yaml` like any other manifest. `hello/secret.sops.yaml` is an example. CI fails if a `*.sops.yaml` file is committed unencrypted.

k8s-dmz has its **own age key**. `.sops.yaml` encrypts files under `kubernetes/dmz/` to it, and only that key is in k8s-dmz's `sops-age` Secret, so a compromised DMZ cluster can't read trusted secrets. Both private keys are in the same `keys.txt` on the Mac (keep both in the password manager). To recreate k8s-dmz's Secret, put only the DMZ key in it (the one under the `# k8s-dmz` comment):

```sh
grep -A2 '# k8s-dmz' "$HOME/Library/Application Support/sops/age/keys.txt" | grep AGE-SECRET-KEY > /tmp/dmz.agekey
kubectl --context admin@k8s-dmz -n flux-system create secret generic sops-age --from-file=age.agekey=/tmp/dmz.agekey
rm /tmp/dmz.agekey
```

**The private key** is in `~/Library/Application Support/sops/age/keys.txt` on the Mac, and in the cluster as Secret `flux-system/sops-age`. It isn't in git. Keep a copy in a password manager. Without it, nothing encrypted can be decrypted. After rebuilding the cluster, recreate the Secret before Flux syncs:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

