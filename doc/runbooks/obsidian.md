# Obsidian LiveSync runbook

[Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync) syncs Obsidian vaults through a CouchDB in namespace `livesync`, on the DMZ nodes. Public at https://obsidian.felixlatulip.ca through the Cloudflare Tunnel, behind Cloudflare Access.

- **Pod:** `couchdb` (couchdb:3.5.3), one replica. The LiveSync settings (CORS, size limits, login required) are in `livesync.ini`.
- **Data:** PVC `couchdb-data` on `local-path`: one DMZ node's disk, no backups. Every device has a full copy of the vault, so if it's lost, redeploy and let a device push everything back.
- **Secrets:** `secret.sops.yaml` holds the CouchDB admin login. Devices use the `obsidian` sync user (below), and its password lives in Vaultwarden. Admin only goes in Obsidian for a rebuild (step 5).
- **Security, three layers:** Cloudflare Access drops anything without the service token, CouchDB needs a login, and the vault is end-to-end encrypted by the plugin, so CouchDB only ever sees encrypted chunks.

## First setup

Do these in order. Nothing is public until step 2, and step 1 has to come first so it's never public without Access.

### 1. Cloudflare Access (Zero Trust dashboard)

1. **Access → Service Auth → Service Tokens:** create `obsidian-livesync`. Copy the Client ID and Client Secret into Vaultwarden (the secret is only shown once).
2. **Access → Applications → Add → Self-hosted:** domain `obsidian.felixlatulip.ca`.
   - Policy: action **Service Auth**, include **Service Token** `obsidian-livesync`. No other policy.
     **Not "Allow":** an Allow policy wants a person to log in, so a valid token still gets a 302 to the login page.
   - Settings → CORS: turn on **Bypass OPTIONS requests to origin**. The CORS preflight can't carry the token headers, so without this the plugin can't connect.

### 2. Tunnel route

**Networks → Tunnels → (the tunnel) → Public Hostname → Add:** `obsidian.felixlatulip.ca` → `http://traefik-dmz.traefik-dmz.svc.cluster.local`.

Check it. Without the token you should get Cloudflare's 403, never CouchDB. With the token (typed in, so the secret isn't in shell history) you should get 200:

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://obsidian.felixlatulip.ca/_up   # 403

read -r CF_ID; read -rs CF_SECRET
curl -s -o /dev/null -w '%{http_code}\n' -H "CF-Access-Client-Id: $CF_ID" \
  -H "CF-Access-Client-Secret: $CF_SECRET" https://obsidian.felixlatulip.ca/_up  # 200
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

printf %s "$sync_pw" | pbcopy   # paste it into Vaultwarden NOW, it isn't saved anywhere else
unset admin_pw sync_pw; kill %1
```

### 4. Obsidian (first device)

Install **Self-hosted LiveSync** and run its setup wizard:

- **End-to-end encryption:** on, passphrase from Vaultwarden, **Obfuscate Properties** on, **Generate a random ID key**. Set before the first sync.
- **Remote:** CouchDB, URI `https://obsidian.felixlatulip.ca` (no trailing slash), database `obsidian`.
- **Custom headers**, one per line:
  ```
  CF-Access-Client-Id: <id>.access
  CF-Access-Client-Secret: <secret>
  ```
- **Use internal API: on.** Required behind Cloudflare Access: with the browser `fetch`, the preflight passes but Access still blocks the real request.
- **Check server requirements** always says "Access forbidden" for a non-admin user (it reads `/_node/_local/_config`). Ignore it, the settings are in `livesync.ini`. Never let it "fix" the config.

### 5. Initialise the server (as admin, once)

The wizard ends with **Restart and Initialise Server**, which deletes and recreates the database. Only server admins can delete one, so as `obsidian` it stops on `DELETE /obsidian/ 401`.

1. Put **user `admin`** and the admin password in the plugin (`sops -d --extract '["stringData"]["COUCHDB_PASSWORD"]' ... | pbcopy`).
2. Run the initialise: tick the boxes, "proceed without a backup" is fine on an empty vault, **Use this device's settings**, size warning **2GB**.
3. The recreated database is **admin-only** (CouchDB 3 default). Reapply the `_security` command from step 3 through a port-forward.
4. Switch the plugin back to user `obsidian`, restart Obsidian, then **Sync Settings → Sync Mode → LiveSync**.

Check that it works: edit a note, then look for `obsidian POST /obsidian/_bulk_docs 201` in `kubectl -n livesync logs deploy/couchdb`.

Other devices: **Copy setup URI** on this one and paste it on the new one (it carries the server, token, E2EE and ID key). Don't paste it anywhere public.

## Troubleshooting

The CouchDB log shows every request with its user and status: `kubectl -n livesync logs deploy/couchdb --since=10m | grep obsidian.felixlatulip.ca`.

| Symptom | Cause |
|---|---|
| Plugin: `Unexpected token '<', "<!DOCTYPE"... is not valid JSON` | Cloudflare Access answered with its HTML page instead of CouchDB. Test the token with the `curl` in step 2. |
| Token `curl` gives 302 | Access policy action is Allow, not Service Auth. |
| Token `curl` gives 403 | Wrong token values, or the token isn't in the policy. |
| Log has `OPTIONS ... 204` but no request after it | Internal API is off. |
| Log has `OPTIONS ... 401` | A header the plugin asks for isn't in `[cors] headers` in `livesync.ini`. |
| Log user is `undefined` with 401 | Wrong sync password. |
| `obsidian ... 401/403` on `/obsidian/` after a rebuild | `_security` wasn't reapplied (step 5.3). |
| Nothing in the log when editing notes | Sync Mode isn't LiveSync, or the plugin needs an Obsidian restart. |

## Maintenance

- **Lost or rotating the sync password:** new password, straight to the clipboard, then update every device:

  ```sh
  kubectl -n livesync port-forward deploy/couchdb 5984 &
  admin_pw=$(sops -d --extract '["stringData"]["COUCHDB_PASSWORD"]' kubernetes/apps/dmz/livesync/secret.sops.yaml)
  couch() { curl -s -u "admin:$admin_pw" -H 'Content-Type: application/json' "$@"; }
  rev=$(couch localhost:5984/_users/org.couchdb.user:obsidian | python3 -c 'import sys,json;print(json.load(sys.stdin)["_rev"])')
  sync_pw=$(openssl rand -hex 24)
  couch -X PUT localhost:5984/_users/org.couchdb.user:obsidian \
    -d "{\"_rev\":\"$rev\",\"name\":\"obsidian\",\"password\":\"$sync_pw\",\"roles\":[],\"type\":\"user\"}"
  printf %s "$sync_pw" | pbcopy   # into Vaultwarden first
  unset admin_pw sync_pw rev; kill %1
  ```

- **Rotating the service token:** create a new token, add it to the Access policy, update every device, then delete the old one.
- **Upgrading:** change the tag in `couchdb.yaml`, within 3.x.
- **Health:** `kubectl -n livesync get pods` and `curl -s localhost:5984/_up` through a port-forward.

## History

- 2026-11-12: first deployed LAN-only in namespace `obsidian` (trusted, Longhorn), then moved to `livesync` in the DMZ. The zone of a namespace can't change, hence the new name. The old `longhorn-retain` PV and its Longhorn volume (never held data) were deleted the same day.
- 2026-11-12: first device set up. Hit, in order: CORS missing the `cf-access-*` headers (fixed in `livesync.ini`), Access policy on Allow instead of Service Auth, internal API needed, and the initialise needing admin. All in the steps above now.
