# Networking, certificates and public apps

## Networking

- **VLANs:** trusted nodes on VLAN 20 (`10.10.20.0/24`, untagged on `vmbr0`), DMZ nodes on VLAN 50 (`10.10.50.0/24`). The DMZ VMs tag their own traffic, so both host bridges are VLAN-aware and carry 50.
- **LoadBalancer IPs:** Cilium hands out `10.10.20.221`–`10.10.20.240` (`infrastructure/cilium-config/`) and answers ARP for them from the trusted nodes (L2 announcements). The old MetalLB range `.200`–`.220` is free.
- **Ingress:** Traefik is at `10.10.20.221`, on ports 80 and 443. On 443 the trusted one serves the `*.lab.felixlatulip.ca` wildcard cert (see [Certificates](#certificates)).
- **Hostnames:** `<app>.lab.felixlatulip.ca`, e.g. https://hello.lab.felixlatulip.ca. Until DNS points there, use `<app>.10.10.20.221.sslip.io` over HTTP.
- **Proxmox UI:** https://pve.lab.felixlatulip.ca, load balanced by Traefik across `goose` (`10.10.20.2`) and `goose2` (`10.10.20.4`), both on `:8006`. A node that fails its health check (every 10s) is dropped until it recovers. A sticky cookie keeps each browser on one node, so consoles don't break. The route is in `apps/trusted/proxmox/` and is read by Traefik's file provider, not an IngressRoute: only ExternalName services can be health checked through the CRDs.
- **Traefik dashboard:** `kubectl -n traefik port-forward deploy/traefik 8080`, then http://localhost:8080/dashboard/

## Certificates

Trusted apps are LAN-only, but their certs are real Let's Encrypt ones, trusted by every device with no setup. cert-manager gets them with a **DNS-01** challenge: it proves ownership of `felixlatulip.ca` by writing a TXT record through the Cloudflare API, so nothing has to be reachable from the internet. Its self-check that the TXT record is live goes over DNS-over-HTTPS to 1.1.1.1. The UniFi gateway intercepts every port-53 query and answers `*.lab` from its local record, which would hide the challenge.

- **One wildcard cert** for `*.lab.felixlatulip.ca`, Traefik's default certificate. It's in `infrastructure/cert-manager-config/wildcard.yaml`. Any Ingress host under `lab.felixlatulip.ca` gets valid HTTPS on 443 without a `tls` section. App names stay out of public Certificate Transparency logs; only the wildcard appears there.
- **Issuers:** `letsencrypt-prod` for real certs, and `letsencrypt-staging` for testing changes (untrusted certs, higher rate limits).
- **Renewal** is automatic, about 30 days before the 90-day expiry. Check status with `kubectl get certificates -A`.
- **Cloudflare token** lives in `cert-manager-config/cloudflare-api-token.sops.yaml`. It's scoped to Zone:DNS:Edit and Zone:Zone:Read on `felixlatulip.ca` only. Rotate it with `sops <file>`.

**DNS for app names.** One local DNS record on the UniFi gateway, `*.lab.felixlatulip.ca` → `10.10.20.221`, covers every app: a new app only needs its Ingress, no DNS change. It's LAN-only. (A DNS-only record in Cloudflare would also work, but it publishes the private IP.)

## Public apps (DMZ)

Public apps run on the DMZ nodes and are reached only through a **Cloudflare Tunnel**: cloudflared (2 replicas, one per DMZ node, `kubernetes/infrastructure/cloudflared/`) opens outbound connections to Cloudflare, so no router ports are open. Cloudflare terminates HTTPS and forwards to `traefik-dmz`, which routes by hostname.

The tunnel `k8s-dmz` (name kept from the old cluster) is managed in the Cloudflare Zero Trust dashboard (Networks → Tunnels). To publish an app:

1. Add it under `kubernetes/apps/dmz/<name>/` with its own Namespace and an Ingress for `<name>.felixlatulip.ca`, and list it in `kubernetes/apps/dmz/kustomization.yaml`. No `tls` section, no `ingressClassName`: Flux puts it in the DMZ zone.
2. Add the namespace to `providers.kubernetesIngress.namespaces` in `kubernetes/infrastructure/traefik-dmz/helmrelease.yaml`. traefik-dmz only watches the namespaces listed there.
3. In the tunnel's public hostnames, add `<name>.felixlatulip.ca` → `HTTP` → `traefik-dmz.traefik-dmz.svc.cluster.local`. Cloudflare creates the DNS record.

The tunnel token is in `infrastructure/cloudflared/tunnel-token.sops.yaml`. To rotate it, refresh the token in the dashboard, copy it, and re-create the file:

```sh
kubectl create secret generic tunnel-token -n cloudflared --from-literal=token="$(pbpaste)" \
  --dry-run=client -o yaml > kubernetes/infrastructure/cloudflared/tunnel-token.sops.yaml
sops -e -i kubernetes/infrastructure/cloudflared/tunnel-token.sops.yaml
```

