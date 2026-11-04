# Storage

**`longhorn`** (k8s-trusted only) is the default StorageClass. Each volume is kept on both nodes (2 replicas), one per Proxmox host, so if one goes down its pods can restart on the other with their data.

- Data lives on a dedicated 50 GB disk per node (`data_disk_size` in `terraform/main.tf`), mounted by Talos at `/var/mnt/longhorn` (`patches/data-disk/longhorn-volume.yaml`, applied to nodes with a data disk). With 2 replicas, usable space is about one disk.
- Talos needs the `iscsi-tools` and `util-linux-tools` extensions for Longhorn; they're in the image list in `terraform/main.tf`.
- UI (no login, so it isn't exposed): `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8000:80`, then http://localhost:8000

**Backups** go to the Unraid NAS over NFS: `nfs://10.10.20.3:/mnt/user/longhorn`. Every volume is backed up daily (7 kept) and weekly on Sundays (4 kept), from `longhorn-config/recurring-jobs.yaml`. Backups are incremental and survive deleting the volume or the whole cluster. To restore: Longhorn UI → Backup → pick a backup → Restore, then point a PVC at the restored volume.

**`longhorn-retain`** is the same, but deleting the PVC keeps the volume (it shows as Released in the Longhorn UI). Use it for data that can't be rebuilt from git, and add the `kustomize.toolkit.fluxcd.io/prune: disabled` annotation so Flux never deletes the PVC either. To reattach a released volume: Longhorn UI → Volume → Create PV/PVC.

**`local-path`** is there for scratch data on k8s-trusted, and is the only storage on k8s-dmz: set `storageClassName: local-path`. Its volumes are directories under `/var/mnt/local-path-provisioner` on one node's system disk, aren't replicated or backed up, and share the ~19 GB EPHEMERAL partition with images and logs.

