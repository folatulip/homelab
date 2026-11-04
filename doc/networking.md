# Networking, certificates and public apps

## Networking

- **VLANs:** k8s-trusted on VLAN 20 (`10.10.20.0/24`, untagged on `vmbr0`). k8s-dmz on VLAN 50 (`10.10.50.0/24`); its VMs tag their own traffic, so both host bridges must be VLAN-aware and carry 50.
- **LoadBalancer IPs:** MetalLB hands out `10.10.20.200`–`10.10.20.220` (trusted) and `10.10.50.200`–`10.10.50.220` (DMZ).
- **Ingress:** Traefik is at `10.10.20.201` (trusted) and `10.10.50.201` (DMZ), on ports 80 and 443. On 443 the trusted one serves the `*.lab.felixlatulip.ca` wildcard cert (see [Certificates](#certificates)).
- **Hostnames:** `<app>.lab.felixlatulip.ca`, e.g. https://hello.lab.felixlatulip.ca. Until DNS points there, use `<app>.10.10.20.201.sslip.io` over HTTP.
- **Traefik dashboard:** `kubectl -n traefik port-forward deploy/traefik 8080`, then http://localhost:8080/dashboard/

## Certificates

k8s-trusted is LAN-only, but its certs are real Let's Encrypt ones, trusted by every device with no setup. cert-manager gets them with a **DNS-01** challenge: it proves ownership of `felixlatulip.ca` by writing a TXT record through the Cloudflare API, so nothing has to be reachable from the internet. Its self-check that the TXT record is live goes over DNS-over-HTTPS to 1.1.1.1. The UniFi gateway intercepts every port-53 query and answers `*.lab` from its local record, which would hide the challenge.

- **One wildcard cert** for `*.lab.felixlatulip.ca`, Traefik's default certificate. It's in `infrastructure/cert-manager-config/wildcard.yaml`. Any Ingress host under `lab.felixlatulip.ca` gets valid HTTPS on 443 without a `tls` section. App names stay out of public Certificate Transparency logs; only the wildcard appears there.
- **Issuers:** `letsencrypt-prod` for real certs, and `letsencrypt-staging` for testing changes (untrusted certs, higher rate limits).
- **Renewal** is automatic, about 30 days before the 90-day expiry. Check status with `kubectl get certificates -A`.
- **Cloudflare token** lives in `cert-manager-config/cloudflare-api-token.sops.yaml`. It's scoped to Zone:DNS:Edit and Zone:Zone:Read on `felixlatulip.ca` only. Rotate it with `sops <file>`.

**DNS for app names.** Point `*.lab.felixlatulip.ca` at Traefik (`10.10.20.201`) in one of two ways:
- a local DNS record on the UniFi gateway: LAN-only, preferred
- a DNS-only (grey cloud) record in Cloudflare: works everywhere, but publishes the private IP

Until then, the `sslip.io` hostnames work over plain HTTP.

## Public apps (k8s-dmz)

Public apps run on k8s-dmz and are reached only through a **Cloudflare Tunnel**: cloudflared (2 replicas, `kubernetes/infrastructure/cloudflared/`) opens outbound connections to Cloudflare, so no router ports are open. Cloudflare terminates HTTPS and forwards to the DMZ Traefik, which routes by hostname.

The tunnel `k8s-dmz` is managed in the Cloudflare Zero Trust dashboard (Networks → Tunnels). To publish an app:

1. Add it under `kubernetes/apps/dmz/<name>/` with an Ingress for `<name>.felixlatulip.ca`, and list it in `kubernetes/apps/dmz/kustomization.yaml`. No `tls` section.
2. In the tunnel's public hostnames, add `<name>.felixlatulip.ca` → `HTTP` → `traefik.traefik.svc.cluster.local`. Cloudflare creates the DNS record.

The tunnel token is in `infrastructure/cloudflared/tunnel-token.sops.yaml`. To rotate it, refresh the token in the dashboard, copy it, and re-create the file:

```sh
kubectl create secret generic tunnel-token -n cloudflared --from-literal=token="$(pbpaste)" \
  --dry-run=client -o yaml > kubernetes/infrastructure/cloudflared/tunnel-token.sops.yaml
sops -e -i kubernetes/infrastructure/cloudflared/tunnel-token.sops.yaml
```

