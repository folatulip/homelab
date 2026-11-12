# Obsidian LiveSync runbook

[Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) syncs Obsidian vaults through a CouchDB in namespace `livesync`, on the DMZ nodes. Public at https://obsidian.felixlatulip.ca through the Cloudflare Tunnel, behind Cloudflare Access.

- **Pod:** `couchdb` (couchdb:3.5.3), one replica. The LiveSync settings (CORS, size limits, login required) are in `livesync.ini`.
- **Data:** PVC `couchdb-data` on `local-path`: one DMZ node's disk, no backups. Every device has a full copy of the vault, so if it's lost, redeploy and let a device push everything back.
- **Secrets:** `secret.sops.yaml` holds the CouchDB admin login. It's only for setup, never put it in Obsidian. Devices use the `obsidian` sync user (below), and its password lives in Vaultwarden.
- **Security, three layers:** Cloudflare Access drops anything without the service token, CouchDB needs a login, and the vault is end-to-end encrypted by the plugin, so CouchDB only ever sees encrypted chunks.

## First setup

Do these in order. Nothing is public until step 2, and step 1 has to come first so it's never public without Access.

### 1. Cloudflare Access (Zero Trust dashboard)

1. **Access → Service Auth → Service Tokens:** create `obsidian-livesync`. Copy the Client ID and Client Secret into Vaultwarden (the secret is only shown once).
2. **Access → Applications → Add → Self-hosted:** domain `obsidian.felixlatulip.ca`.
   - Policy: action **Service Auth**, include **Service Token** `obsidian-livesync`. No other policy.
   - Settings → CORS: turn on **Bypass OPTIONS requests to origin**. The CORS preflight can't carry the token headers, so without this the plugin can't connect.

### 2. Tunnel route

**Networks → Tunnels → (the tunnel) → Public Hostname → Add:** `obsidian.felixlatulip.ca` → `http://traefik-dmz.traefik-dmz.svc.cluster.local`.

Check it: without the token you should get Cloudflare's Access page, never CouchDB.

```sh
curl -sI https://obsidian.felixlatulip.ca | head -1   # expect 302 or 403
```

### 3. Sync user and database

Through a port-forward, so the admin login never goes over the internet:

```sh
kubectl -n livesync port-forward deploy/couchdb 5984 &
admin_pw=$(sops -d --extract '["stringData"]["COUCHDB_PASSWORD"]' kubernetes/apps/dmz/livesync/secret.sops.yaml)
sync_pw=$(openssl rand -hex 24)
couch() { curl -sf -u "admin:$admin_pw" -H 'Content-Type: application/json' "$@"; }

couch -X PUT localhost:5984/_users/org.couchdb.user:obsidian \
  -d "{\"name\":\"obsidian\",\"password\":\"$sync_pw\",\"roles\":[],\"type\":\"user\"}"
couch -X PUT localhost:5984/obsidian
# Only the obsidian user can read or write this database
couch -X PUT localhost:5984/obsidian/_security \
  -d '{"admins":{"names":[],"roles":[]},"members":{"names":["obsidian"],"roles":[]}}'

printf %s "$sync_pw" | pbcopy   # paste it into Vaultwarden, it isn't saved anywhere else
unset admin_pw sync_pw; kill %1
```

### 4. Obsidian (first device)

Install **Self-hosted LiveSync**, then in its settings:

- **Remote:** URI `https://obsidian.felixlatulip.ca`, user `obsidian`, the sync password, database `obsidian`.
- **Custom headers:** `CF-Access-Client-Id` and `CF-Access-Client-Secret` with the token values.
- **End-to-end encryption:** on, with a passphrase from Vaultwarden. Also turn on path obfuscation. Do this before the first sync.

Then use the plugin's "Copy setup URI" to add the other devices. The URI is encrypted with a passphrase, but still don't paste it anywhere public.

## Maintenance

- **Rotating the service token:** create a new token, add it to the Access policy, update every device, then delete the old one.
- **Rotating the sync password:** same `PUT /_users/org.couchdb.user:obsidian` as above, but the body also needs the current `_rev` (`GET` it first). Then update every device.
- **Upgrading:** change the tag in `couchdb.yaml`, within 3.x.
- **Health:** `kubectl -n livesync get pods` and `curl -s localhost:5984/_up` through a port-forward.

## History

- 2026-11-12: first deployed LAN-only in namespace `obsidian` (trusted, Longhorn), then moved to `livesync` in the DMZ. The zone of a namespace can't change, hence the new name. Flux pruned `obsidian`, but its `longhorn-retain` PV stays behind as `Released`. It never held data, so delete it: `kubectl get pv | grep obsidian/couchdb-data`, then `kubectl delete pv <name>` and remove the volume in the Longhorn UI.
