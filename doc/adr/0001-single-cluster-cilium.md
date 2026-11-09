# ADR 0001: One cluster with Cilium, DMZ on its own VLAN

- **Status:** Proposed
- **Date:** 2026-11-08
- **Roadmap:** [3. One cluster](../roadmap.md#3-one-cluster)

## Context

Right now there are two Talos clusters, one per VLAN:

| Cluster | VLAN | Nodes | RAM | Runs |
|---|---|---|---|---|
| k8s-trusted | 20 | cp1 (`goose`), w1 (`goose2`) | 12 + 6 GB | vaultwarden, sure, proxmox route, Longhorn, cert-manager |
| k8s-dmz | 50 | dmz-1 (`goose`), dmz-2 (`goose2`) | 4 + 3 GB | cloudflared, hello |

The isolation is strong (separate API server, etcd, Flux, age key, and a firewall between VLANs), but it costs a lot:

- Two control planes on two small hosts. k8s-dmz uses 7 GB of RAM to run one public app.
- Every infra piece (Flux, MetalLB, Traefik, local-path) is deployed and upgraded twice.
- Flannel has no NetworkPolicy support, so inside k8s-trusted every pod can reach every other pod.

The hosts are almost full: `goose` has ~6 GB free (23 GB total) and `goose2` ~4 GB free (19 GB total).

## Decision

### 1. One cluster, two node pools

One Talos cluster, `k8s-geese`. Trusted nodes are on VLAN 20, DMZ nodes on VLAN 50 (the VM tags its own traffic, same as today).

| Node | VM ID | IP | Host | Role | Final RAM |
|---|---|---|---|---|---|
| k8s-geese-cp1 | 601 | 10.10.20.60 | `goose` | control plane + trusted worker | 12 GB |
| k8s-geese-w1 | 611 | 10.10.20.61 | `goose2` | trusted worker | 6 GB |
| k8s-geese-dmz1 | 651 | 10.10.50.60 | `goose` | DMZ worker | 3 GB |
| k8s-geese-dmz2 | 652 | 10.10.50.61 | `goose2` | DMZ worker | 3 GB |

Final footprint is 15 GB on `goose` and 9 GB on `goose2`, about the same as today. The control plane only runs trusted workloads.

Why keep VLAN 50 at all if Cilium does the isolation: Cilium masquerades pod egress to the node IP. DMZ pods leave the node from `10.10.50.x`, so the UniFi firewall still blocks them from the NAS, Proxmox and the rest of the LAN, even if a network policy is wrong. That's a second layer that doesn't depend on Kubernetes.

### 2. Cilium as the CNI

- `cni: none` and kube-proxy off in Talos (`KubeProxyConfig` with `enabled: false`; deleting the document isn't enough, Talos falls back to enabled). Cilium replaces kube-proxy and talks to the API through KubePrism (`localhost:7445`).
- **VXLAN tunnel** between nodes, so pod traffic between VLANs only needs the node IPs to reach each other.
- **LB IPAM + L2 announcements** replace MetalLB. Only the trusted nodes announce, since an L2 announcement only works on the node's own subnet.
- **Hubble** on, to see what the policies drop.

**Bootstrap:** Flux can't run before a CNI exists. Cilium is installed once with `helm install` from a bootstrap script, using the same values file as the Flux HelmRelease. Then the HelmRelease (same name and namespace) takes over the release. Verified in step 5: helm-controller upgraded the bootstrap release in place (`cilium.v2`), no reinstall.

### 3. Zone label and placement

- Every node has `node-restriction.kubernetes.io/zone: trusted|dmz`. Kubelets can't set labels under that prefix (NodeRestriction), so a compromised DMZ node can't relabel itself as trusted. Talos writes node labels with the node's own credentials, so it can't set this one: Terraform sets it as admin with `kubectl label` once the node registers (`terraform_data.zone_label` in the talos-cluster module).
- DMZ nodes also have a `zone=dmz:NoSchedule` taint.
- Every namespace has a `felixlatulip.ca/zone: trusted|dmz` label.
- DMZ pods are pinned with a **required** node affinity on the zone label. Trusted pods are kept off DMZ nodes by the taint: a node can't change its own taints or delete its own Node object (NodeRestriction), so a compromised DMZ node can't remove it.
- Two **ValidatingAdmissionPolicies** (built in, no Kyverno) enforce it (`infrastructure/zone-isolation/`):
  - every namespace has `felixlatulip.ca/zone: trusted|dmz` (except built-ins like `kube-system`), and the zone can't change afterwards
  - pods in a dmz namespace need the DMZ affinity on every node selector term; pods anywhere else can't tolerate the DMZ taint; no pod can set `spec.nodeName` (it skips the scheduler). `kube-system` is skipped, the Cilium agent runs on every node.
- Flux adds the zone label to every namespace, and the affinity, toleration and `automountServiceAccountToken: false` to every DMZ Deployment, with Kustomization `patches` in `kubernetes/cluster/`. Apps don't repeat it. HelmReleases in the DMZ need it in their values, and the admission policy catches it if forgotten.
- DMZ namespaces enforce Pod Security `restricted`.

### 4. Network policies

Cilium cluster-wide policies, selected by the namespace zone label:

- **DMZ pods:** egress only to other DMZ pods, cluster DNS and the internet (`0.0.0.0/0` except private ranges). Ingress only from other DMZ pods. Only `traefik-dmz` can reach the API server.
- **Trusted pods:** ingress deny from any DMZ endpoint. A deny wins over any allow, so this holds even if the DMZ policy is wrong.
- Default-deny in DMZ namespaces. Trusted namespaces stay default-allow for now (can be tightened later, one app at a time).

### 5. Two Traefik instances

| | Trusted | DMZ |
|---|---|---|
| Release | `traefik` in `traefik` | `traefik-dmz` in `traefik-dmz` |
| Matches | `ingressClassName: traefik` (default class) | annotation `kubernetes.io/ingress.class: traefik-dmz` |
| RBAC | ClusterRole | Roles in an allowlist of namespaces |
| Service | LoadBalancer `10.10.20.221` | ClusterIP only |
| Runs on | trusted nodes | DMZ nodes |

A single Traefik would be a hole: cloudflared forwards public requests to Traefik, and Traefik routes by `Host` header, so a public request with `Host: vaultwarden.lab.felixlatulip.ca` would reach Vaultwarden.

Each Traefik is pinned to its class with `providers.kubernetesIngress.ingressClass`, otherwise both would serve both.

The chart's ClusterRole can read every Secret in the cluster, which the public Traefik must never have. So `traefik-dmz` uses `rbac.namespaced: true`: Roles only in the namespaces listed in its values. That mode can't read IngressClass objects, so it matches the old annotation instead of `ingressClassName`; Flux sets the annotation on every Ingress in `apps/dmz/`. A new DMZ app needs its namespace added to that list.

The DMZ Traefik doesn't need a LAN IP: cloudflared reaches it through its ClusterIP. That means no LB pool on VLAN 50 at all. The tunnel's public hostnames move to `traefik-dmz.traefik-dmz.svc.cluster.local`.

### 6. Storage

- Longhorn runs only on trusted nodes (node selector + disks only on cp1 and w1). Trusted data never sits on a DMZ node's disk, and Longhorn replication traffic stays on VLAN 20.
- DMZ apps use local-path, same as today.

### 7. Secrets: one age key

One Flux means kustomize-controller holds every decryption key anyway, so two keys no longer keep DMZ secrets apart in the cluster. The real boundary is now RBAC: DMZ service accounts can't read Secrets, and the node authorizer only gives a node the Secrets of its own pods.

- Keep the trusted key. Re-encrypt the tunnel token with it (`sops updatekeys`), remove the DMZ rule from `.sops.yaml`.
- Retire the DMZ key after k8s-dmz is gone.

### 8. Firewall (UniFi)

Only between node IPs, not whole subnets. The firewall is stateful, so replies are allowed.

| From | To | Port | Why |
|---|---|---|---|
| DMZ nodes | cp1 | TCP 6443 | Kubernetes API |
| DMZ nodes | cp1 | TCP 50001 | Talos trustd (node certs) |
| DMZ nodes ↔ trusted nodes | | UDP 8472 | Cilium VXLAN |
| DMZ nodes ↔ trusted nodes | | TCP 4240 | Cilium health checks |
| trusted nodes | DMZ nodes | TCP 10250 | kubelet (logs, exec) |
| trusted nodes | DMZ nodes | TCP 4244 | Hubble |
| Mac | DMZ nodes | TCP 50000 | talosctl |
| cp1 | DMZ nodes | TCP 50000 | talosctl through cp1 (the talosconfig endpoint) |

### 9. IPs and DNS cutover

- Trusted LB pool: `10.10.20.221`–`10.10.20.240`. New range so it never overlaps MetalLB's `.200`–`.220` while both clusters run.
- Each app is cut over with its own UniFi DNS record (`vaultwarden.lab` → `10.10.20.221`), which wins over the wildcard. Rollback = delete the record.
- When everything is moved, point the `*.lab` wildcard at `.221` and delete the per-app records.
- The new cluster gets its own `*.lab` wildcard cert from cert-manager.

### 10. Flux layout

One entry point at `kubernetes/cluster/` (the old `kubernetes/clusters/` folder goes away with the old clusters). Kustomizations `apps-trusted` (path `apps/trusted`) and `apps-dmz` (path `apps/dmz`, with the zone patches from section 3).

## Migration order

There isn't enough RAM to run the new cluster next to both old ones, so k8s-dmz goes first. It only runs `hello`, so the public outage costs almost nothing.

1. `feat/talos-module-cilium`: node-level VLAN, zone label/taint, `cni: none`, kube-proxy off as module inputs. `terraform plan` must show no change to the current clusters.
2. `feat/cilium-infra`: `infrastructure/cilium` (+ config), `traefik-dmz`, `kubernetes/cluster/` entry point. Inert until the cluster exists.
3. `feat/zone-isolation`: admission policy, network policies, Flux patches for `apps/dmz`. Inert too.
4. `chore/decommission-k8s-dmz`: destroy k8s-dmz, remove `kubernetes/clusters/k8s-dmz`. **Public outage starts.** Frees ~7 GB.
5. `feat/k8s-geese-cluster`: create the cluster small (cp1 6 GB, w1 4 GB, dmz1 3 GB), bootstrap Cilium, bootstrap Flux. cloudflared + hello come up. **Outage ends.** Firewall rules from section 8.
6. **Isolation tests** before anything trusted moves, from a pod in a DMZ namespace:
   - `curl` a trusted Service: must fail
   - `curl 10.10.20.3` (NAS) and `10.10.20.2:8006` (Proxmox): must fail
   - `curl https://example.com`: must work
   - a pod without the DMZ affinity in a DMZ namespace: must be rejected
7. `feat/migrate-<app>`, one per PR: proxmox route → vaultwarden → sure. Longhorn backup on k8s-trusted, restore on k8s-geese, DNS record, check, scale old one to 0.
8. `chore/decommission-k8s-trusted`: destroy, then resize cp1 to 12 GB and w1 to 6 GB, add dmz2. Remove MetalLB and `kubernetes/clusters/`.
9. `chore/readme-single-cluster`: README, diagram, docs. Set this ADR to **Accepted**.

## Consequences

**Better**
- One control plane, one Flux, one copy of every infra piece.
- Network policies and Hubble for the trusted side too, not just the DMZ.
- Same RAM as today (24 GB vs 25 GB), but the DMZ nodes no longer run etcd and an API server, so all of their RAM goes to apps.

**Worse**
- **The boundary is softer.** Before, a compromised DMZ cluster was a separate cluster. Now, root on a DMZ node gets kubelet credentials and access to the VXLAN overlay. In tunnel mode Cilium carries the pod identity in the VXLAN header, so a node root could forge it and get past the policies. What's left: Talos is immutable with no shell, DMZ pods run `restricted`, the zone label can't be changed by the node, and VLAN 50 still blocks the LAN.
- **One failure domain.** A bad Cilium config or Kubernetes upgrade takes down public and private apps together.
- **Firewall holes** from VLAN 50 to VLAN 20 (section 8), limited to node IPs and ports.
- Single control plane, same as today (HA is roadmap item 8).

## Alternatives

- **Keep two clusters, add Cilium to both.** Hardest boundary, but keeps the 7 GB cost and double maintenance on hosts that are already full.
- **One cluster, every node on VLAN 20, DMZ by policy only.** Simplest firewall, but DMZ egress would leave from a trusted IP, so the firewall can't help if a policy is wrong.
- **Multus with a VLAN 50 interface in DMZ pods.** Pods get real VLAN 50 IPs. More moving parts (Multus on Talos, IPAM for VLAN 50) for little gain over DMZ nodes.

## Open questions

- [ ] Cluster name `k8s-geese`?
- [ ] Are `10.10.20.60-61`, `10.10.50.60-61` and `10.10.20.221-240` outside the UniFi DHCP ranges?
- [ ] Do the hosts have disk space for two more 50 GB Longhorn disks while both clusters run?
- [ ] Does anything on the LAN use the DMZ Traefik at `10.10.50.201` directly? (Section 5 drops it.)
