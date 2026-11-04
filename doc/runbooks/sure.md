# Sure runbook

[Sure](https://github.com/we-promise/sure) (personal finance) runs in namespace `sure` on k8s-trusted, LAN only: https://sure.lab.felixlatulip.ca. It came from LXC 105 on goose (Docker Compose) on 2026-11-01.

- **Pods:** `sure` (Rails web + Sidekiq worker in one pod, since both need the uploads volume), `sure-db` (postgres:16.14), `sure-redis` (redis:8.8.0).
- **Data:** PVCs `sure-db`, `sure-storage` (uploads) and `sure-redis` are on `longhorn-retain` and never pruned by Flux.
- **Secrets:** `secret.sops.yaml` holds the Postgres login, `SECRET_KEY_BASE` and the three `ACTIVE_RECORD_ENCRYPTION_*` keys. **Those keys encrypt fields in the database: if they're lost or changed, that data can't be read.** Keep a copy in your password manager.
  `SECRET_KEY_BASE` also encrypts API keys saved in sure's settings (OpenAI, Anthropic, Twelve Data, ...), so once any are saved, changing it makes them unreadable. Otherwise it only signs logins, and a new one just logs everyone out.
- **Rotating the Postgres password:** change `POSTGRES_PASSWORD` with `sops`, merge, wait for Flux to update the Secret, then set it in Postgres and restart the app:

  ```sh
  kubectl -n sure get secret sure-env -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d |
    kubectl -n sure exec -i sure-db-0 -- sh -c 'read -r p; echo "ALTER USER CURRENT_USER PASSWORD :'\''p'\'';" | psql -q -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v p="$p"'
  kubectl -n sure rollout restart deploy/sure
  ```
- **Backups**, three layers:
  1. `sure-db-dump` CronJob: `pg_dump` every night at 07:00 UTC into the `sure-db-dumps` PVC, 14 days kept. Each dump is test-read before it's kept.
  2. Longhorn backs up every sure volume (dumps included) to the NAS daily at 08:00 UTC.
  3. The pre-migration copy on the NAS: `data/sure-migration-20261101/` (vzdump of LXC 105, Postgres dumps, row counts). The vzdump includes the old `.env`, so it holds the encryption keys next to the data: guard it like the data.
- **Upgrading:** change the image tag and digest in `app.yaml` (both containers). Take a manual dump first: `kubectl -n sure create job --from=cronjob/sure-db-dump pre-upgrade`. The app runs its migrations on start. Postgres stays on 16.x: a major version needs a dump and restore.

Restore the database from a nightly dump:

1. Set `replicas: 0` in `app.yaml`, push, and wait for the `sure` pod to stop.
2. Start a pod that has the dumps and the DB login, then restore into it:

   ```sh
   kubectl -n sure apply -f - <<'EOF'
   apiVersion: v1
   kind: Pod
   metadata: { name: restore }
   spec:
     securityContext: { runAsUser: 999, runAsGroup: 999, runAsNonRoot: true, seccompProfile: { type: RuntimeDefault } }
     containers:
       - name: pg
         image: postgres:16.14
         command: ["sleep", "infinity"]
         env:
           - { name: PGHOST, value: sure-db }
           - { name: PGUSER, valueFrom: { secretKeyRef: { name: sure-env, key: POSTGRES_USER } } }
           - { name: PGPASSWORD, valueFrom: { secretKeyRef: { name: sure-env, key: POSTGRES_PASSWORD } } }
           - { name: PGDATABASE, valueFrom: { secretKeyRef: { name: sure-env, key: POSTGRES_DB } } }
         securityContext: { allowPrivilegeEscalation: false, capabilities: { drop: ["ALL"] } }
         volumeMounts: [{ name: dumps, mountPath: /dumps }]
     volumes: [{ name: dumps, persistentVolumeClaim: { claimName: sure-db-dumps } }]
   EOF
   kubectl -n sure exec restore -- ls -lh /dumps
   kubectl -n sure exec restore -- pg_restore --clean --if-exists --exit-on-error -d sure_production /dumps/<file>.dump
   kubectl -n sure delete pod restore
   ```

   The dumps volume attaches to one node at a time, so the restore fails if the nightly job is running at the same moment.
3. Set `replicas: 1` again and push.

