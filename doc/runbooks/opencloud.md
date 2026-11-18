# OpenCloud runbook

[OpenCloud](https://opencloud.eu) (file sync and share) runs in namespace `opencloud` on the trusted nodes, LAN only: https://opencloud.lab.felixlatulip.ca. One pod runs every service (`opencloud server`), like the official compose file.

- **Data:**
  - `opencloud-config` (Longhorn, 1Gi): `/etc/opencloud/opencloud.yaml`, made by `opencloud init` on the first boot. It holds every generated secret (JWT, machine auth, IDP keys...). **If it's lost, the user files can't be matched to their accounts anymore.**
  - `opencloud-data` (Longhorn, 5Gi): `/var/lib/opencloud` minus the files: accounts (idm), NATS, search index, thumbnails, space metadata.
  - `opencloud-files` (NAS, NFS): `/var/lib/opencloud/storage/users` = Unraid share `cloud`. Static PV, mounted by the kubelet on the trusted nodes.
  - All three have `Retain`/no-prune, so Flux never deletes them.
- **Storage driver:** `decomposed` (metadata in `.mpk` files next to the blobs). The default `posix` driver needs xattrs on the share, and Unraid over NFS isn't a safe bet for that. It can't be changed once there are files. On the NAS the files are stored by ID, not by name: use OpenCloud (or WebDAV) to get them out, not the share.
- **Admin login:** user `admin`, password from `secret.sops.yaml` (`IDM_ADMIN_PASSWORD`). It's only read on the first boot. After that, change it in the web UI and update your password manager, not the secret.

## NFS export on Unraid (one time, before the first deploy)

The `cloud` share is exported read-only to `*` by default. OpenCloud needs it writable from the trusted nodes only:

Shares → cloud → NFS Security Settings:

- Export: **Yes**
- Security: **Private**
- Rule: `10.10.20.60(sec=sys,rw,all_squash,anonuid=99,anongid=100) 10.10.20.61(sec=sys,rw,all_squash,anonuid=99,anongid=100)`

`all_squash` maps every write to `nobody:users`, like any other Unraid share, so the pod's uid 1000 doesn't matter. DMZ nodes (`10.10.50.x`) aren't in the rule, and UniFi blocks them anyway (ADR 0001).

The PV mounts with **NFSv3** and `local_lock=all`, so keep NFSv3 on in Settings → NFS. OpenCloud's WebDAV locks take an exclusive `flock` on files it opened read-only. NFS servers refuse that (`Bad file descriptor`), so the locks have to stay on the client. That's safe because the OpenCloud pod is the only client. NFSv4 ignores `local_lock`. Tested on 2026-11-18. Don't touch the share from other machines, it's OpenCloud's.

Check it before merging (writes, renames and deletes a test folder):

```sh
kubectl run nfs-check --rm -i --restart=Never --image=busybox:1.38 --overrides='
{"spec":{"securityContext":{"runAsUser":1000,"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},
"containers":[{"name":"nfs-check","image":"busybox:1.38",
"command":["sh","-c","set -e; d=/c/nfs-check; mkdir $d; echo hi > $d/a; mv $d/a $d/b; rm -r $d; echo OK"],
"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}},
"volumeMounts":[{"name":"c","mountPath":"/c"}]}],
"volumes":[{"name":"c","nfs":{"server":"10.10.20.3","path":"/mnt/user/cloud"}}]}}'
```

It has to print `OK`. `Read-only file system` = the rule isn't saved yet. An inline `nfs:` volume can't set mount options, so this doesn't test the locks.

## Backups

- Longhorn backs up `opencloud-config` and `opencloud-data` to the NAS daily (longhorn-config).
- `opencloud-files` is on the NAS itself, protected by Unraid parity only. It's not in any backup yet (roadmap 7, 3-2-1 backups).
- The Longhorn backup and the NAS files are taken at different times, so a restore can be a bit out of sync. Scale to 0 first for a clean copy: set `replicas: 0`, push, wait, then take a manual Longhorn backup.

## Upgrading

Change the tag in `app.yaml`. Read the [release notes](https://github.com/opencloud-eu/opencloud/releases) for majors first, some need `opencloud` CLI migrations. Take a manual Longhorn backup of both volumes before.

## Clients

Desktop/mobile clients log in with `https://opencloud.lab.felixlatulip.ca`, so they only sync on the LAN (or through a VPN).
