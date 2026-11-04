<div align="center">

# FO's Homelab
Everything that runs the 🪿 geese clusters, declared in code.

</div>

<div align="center">

![Wifi](https://img.shields.io/badge/LAN-UP-2ea043?style=for-the-badge&logo=ubiquiti&logoColor=white)
![Age](https://img.shields.io/badge/Age-0d-2ea043?style=for-the-badge&labelColor=1a1a1a)
![Uptime](https://img.shields.io/badge/Uptime-0d-2ea043?style=for-the-badge&labelColor=1a1a1a)
![Nodes](https://img.shields.io/badge/Nodes-2-326CE5?style=for-the-badge&labelColor=1a1a1a)
![Pods](https://img.shields.io/badge/Pods-0-326CE5?style=for-the-badge&labelColor=1a1a1a)
![CPU](https://img.shields.io/badge/CPU-0%25-E57000?style=for-the-badge&labelColor=1a1a1a)
![Memory](https://img.shields.io/badge/Memory-0%25-E57000?style=for-the-badge&labelColor=1a1a1a)
![Alerts](https://img.shields.io/badge/Alerts-0-2ea043?style=for-the-badge&labelColor=1a1a1a)

</div>

<div align="center">

![Kubernetes][k8s-shield]
![Proxmox][proxmox-shield]
![Terraform][terraform-shield]
![Talos][talos-shield]
![Flux][flux-shield]

</div>

## Overview

My homelab as code. Terraform builds the Proxmox VMs and two Talos Kubernetes clusters. Flux deploys everything else from this repo.

> **What is a homelab?**
>
> Why rent the cloud when you can build your own? A homelab lets you self-host services, experiment freely, and get hands-on practice for certifications, right from your home.

## Apps

| App | What | URL |
|---|---|---|
| [Vaultwarden](https://github.com/dani-garcia/vaultwarden) | Password manager | `vaultwarden.lab.felixlatulip.ca` |
| [Sure](https://github.com/we-promise/sure) | Personal finance | `sure.lab.felixlatulip.ca` |

## Network Topology
```mermaid
---
config:
  theme: base
  flowchart:
    htmlLabels: true
    curve: basis
    nodeSpacing: 30
    rankSpacing: 22
    padding: 10
    subGraphTitleMargin:
      top: 6
      bottom: 6
  themeVariables:
    darkMode: true
    background: "#141414"
    fontFamily: "Inter, Segoe UI, Helvetica, Arial, sans-serif"
    fontSize: 15px
    primaryColor: "#1f1f1f"
    primaryTextColor: "#f2f2f2"
    primaryBorderColor: "#555"
    lineColor: "#8a8a8a"
    clusterBkg: "#1b1b1d"
    clusterBorder: "#3a3a3d"
    titleColor: "#f2f2f2"
---
flowchart TB
    NET["<div style='width:170px;text-align:center;line-height:1.35'><b>🌐 Internet</b></div>"]
    GW["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/unifi.png' style='width:30px;height:30px;max-width:30px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>UniFi Gateway Fiber</b></div>"]
    WIFI["<div style='width:150px;text-align:center;line-height:1.35'><b>📶 VLAN10</b><br/>Wi-Fi</div>"]
    IOT["<div style='width:150px;text-align:center;line-height:1.35'><b>💡 VLAN30</b><br/>IoT</div>"]

    NET ==> GW
    GW --> WIFI
    GW --> S1
    GW --> S2
    GW --> NAS
    GW --> IOT

    subgraph NAS["<b>goose-nas (Unraid)</b>"]
        direction TB
        H3["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/unraid.png' style='width:22px;height:22px;max-width:22px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span>i9-9900K · 16GB · 32TB</div>"]
        PBS["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proxmox-backup-server.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>PBS</b><br/><small>VM · 3GB</small></div>"]
        QDEV["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proxmox.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>QDevice</b><br/><small>VM · quorum</small></div>"]
        H3 ~~~ PBS ~~~ QDEV
    end

    subgraph S2["<b>goose-s2-pve</b>"]
        direction TB
        H2["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proxmox.png' style='width:22px;height:22px;max-width:22px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span>i5-6500T · 20GB · 2.5GbE</div>"]
        HAOS["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/home-assistant.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>HAOS</b><br/><small>VM · 3GB</small></div>"]
        UOS["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/unifi.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>UniFi OS Server</b><br/><small>VM · 3GB</small></div>"]
        PDM["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proxmox.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>PDM</b><br/><small>LXC · 1GB</small></div>"]
        K8TW["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>k8s-trusted-w1</b><br/><small>Worker · 6GB</small></div>"]
        K8D2["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>k8s-dmz-2</b><br/><small>Worker · 3GB</small></div>"]
        H2 ~~~ HAOS ~~~ UOS ~~~ PDM ~~~ K8TW ~~~ K8D2
    end

    subgraph S1["<b>goose-s1-pve</b>"]
        direction TB
        H1["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/proxmox.png' style='width:22px;height:22px;max-width:22px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span>i5-8600K · 24GB · 10GbE</div>"]
        K8TCP["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>k8s-trusted-cp1</b><br/><small>CP + worker · 12GB</small></div>"]
        K8D1["<div style='width:200px;text-align:center;line-height:1.35'><span style='display:flex;justify-content:center;gap:6px;margin-bottom:4px'><img src='https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/kubernetes.png' style='width:26px;height:26px;max-width:26px;object-fit:contain;display:inline;vertical-align:middle;margin:0 3px' /></span><b>k8s-dmz-1</b><br/><small>CP + worker · 4GB</small></div>"]
        H1 ~~~ K8TCP ~~~ K8D1
    end

    subgraph LEGEND[" "]
        direction LR
        L1["<div style='width:150px;text-align:center;line-height:1.35'>Mgmt · VLAN1</div>"]
        L2["<div style='width:150px;text-align:center;line-height:1.35'>Trusted · VLAN20</div>"]
        L3["<div style='width:150px;text-align:center;line-height:1.35'>DMZ · VLAN50</div>"]
        L1 ~~~ L2 ~~~ L3
    end
    S2 ~~~ LEGEND

    classDef core fill:#1f1f22,stroke:#6b6b70,stroke-width:1.5px,color:#f5f5f5,rx:10,ry:10
    classDef hdr fill:transparent,stroke:transparent,color:#a8a8ad
    classDef mgmt fill:#3d3d3a,stroke:#9a9a94,stroke-width:1.5px,color:#e8e8e3,rx:10,ry:10
    classDef trusted fill:#0b4d3f,stroke:#3fd1a2,stroke-width:1.5px,color:#c9f5e6,rx:10,ry:10
    classDef dmz fill:#7a2d14,stroke:#ff8a5c,stroke-width:1.5px,color:#ffd9c9,rx:10,ry:10

    class NET,GW core
    class H1,H2,H3 hdr
    class WIFI,IOT,UOS,PDM,L1 mgmt
    class K8TCP,K8TW,HAOS,PBS,QDEV,L2 trusted
    class K8D1,K8D2,L3 dmz

    style S1 fill:#1b1b1d,stroke:#3a3a3d,stroke-width:2px
    style S2 fill:#1b1b1d,stroke:#3a3a3d,stroke-width:2px
    style NAS fill:#1b1b1d,stroke:#3a3a3d,stroke-width:2px
    style LEGEND fill:transparent,stroke:transparent

    linkStyle 0 stroke:#3fd1a2,stroke-width:3px
```

## Clusters

| Cluster | VLAN | Purpose |
|---|---|---|
| `k8s-trusted` | 20 | LAN-only services |
| `k8s-dmz` | 50 | Public apps, via Cloudflare Tunnel |

Each cluster has one node per Proxmox host, so either host can go down. Control planes also run workloads.

| Node | IP | Role | Host | RAM |
|---|---|---|---|---|
| k8s-trusted-cp1 | 10.10.20.50 | control plane | `goose` | 12 GB |
| k8s-trusted-w1 | 10.10.20.51 | worker | `goose2` | 6 GB |
| k8s-dmz-1 | 10.10.50.50 | control plane | `goose` | 4 GB |
| k8s-dmz-2 | 10.10.50.51 | worker | `goose2` | 3 GB |

## Directories

```sh
📁 .github/workflows                # CI checks + auto-PR on push
📁 doc                              # runbooks and how-tos
│   └── 📁 templates/helm-app       # starting point for a new Helm app
📁 scripts
├── 📁 ci                           # validate Talos/Kubernetes, lint commits
├── 📁 git-hooks                    # local commit-msg hook
└── 📁 readme                       # generates the topology diagram
📁 terraform                        # Proxmox VMs + Talos clusters
├── 📄 main.tf                      # clusters, node sizes, Talos version, dmz_enabled
├── 📄 proxmox.tf                   # Proxmox host settings: network, VLANs, storage
└── 📁 modules
    ├── 📁 proxmox-base             # per-host network/DNS/time, NAS storages
    ├── 📁 proxmox-vm               # one VM, cloned from a template
    ├── 📁 talos-image              # Talos boot ISO + extensions (Image Factory)
    └── 📁 talos-cluster            # VMs + Talos bootstrap for one cluster
        └── 📁 patches              # Talos machine config patches
📁 kubernetes
├── 📁 clusters                     # Flux entry points, one per cluster
│   ├── 📁 k8s-trusted
│   │   ├── 📁 flux-system          # Flux itself (written by flux bootstrap)
│   │   ├── 📄 infrastructure.yaml  # which add-ons to apply, in what order, with this cluster's IPs
│   │   └── 📄 apps.yaml            # applies apps/ after ingress + storage are ready
│   └── 📁 k8s-dmz                  # same layout, points at dmz/
├── 📁 infrastructure               # add-ons, shared by both clusters
│   ├── 📁 metallb                  # load balancer controller
│   ├── 📁 metallb-config           # IP pool, set per cluster (L2 mode)
│   ├── 📁 traefik                  # ingress controller, fixed IP per cluster
│   ├── 📁 local-path-provisioner   # StorageClass "local-path" (node-local scratch)
│   ├── 📁 longhorn                 # default StorageClass "longhorn" (replicated), trusted only
│   ├── 📁 longhorn-config          # NAS backup schedule, "longhorn-retain" class, trusted only
│   ├── 📁 cert-manager             # issues TLS certificates, trusted only
│   └── 📁 cert-manager-config      # Let's Encrypt issuers, Cloudflare token, *.lab wildcard cert
├── 📁 dmz                          # k8s-dmz only (secrets use the DMZ age key)
│   ├── 📁 cloudflared              # Cloudflare Tunnel connector
│   └── 📁 apps                     # public apps (hello = tunnel test page)
└── 📁 apps                         # k8s-trusted apps
    ├── 📄 kustomization.yaml       # list of apps Flux deploys
    ├── 📁 hello                    # example app
    ├── 📁 sure                     # personal finance
    ├── 📁 vaultwarden              # password manager (Helm)
    └── 📁 pvc-test                 # throwaway storage check (not deployed by Flux)
```

## Deployment

**1. Build the VMs and clusters**

```sh
terraform -chdir=terraform apply
terraform -chdir=terraform output -raw trusted_kubeconfig > ~/.kube/config
```

**2. Add the sops key** (before Flux, or secrets fail to decrypt)

```sh
kubectl create namespace flux-system
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey="$HOME/Library/Application Support/sops/age/keys.txt"
```

**3. Bootstrap Flux** (with a short-lived `GITHUB_TOKEN`)

```sh
flux bootstrap github --owner=folatulip --repository=homelab --personal \
  --branch=main --path=kubernetes/clusters/k8s-trusted
```

For k8s-dmz, use the `dmz_*` outputs, the DMZ key only, and `--path=kubernetes/clusters/k8s-dmz`. Details in [doc/rebuild.md](doc/rebuild.md).

## Workflow

Flux watches `main`. Merge a PR and it's live within a minute. Delete a file and Flux deletes it from the cluster.

```sh
flux reconcile kustomization flux-system --with-source   # sync now
flux get kustomizations                                  # status
```

Per-cluster values (`LB_RANGE`, `TRAEFIK_IP`) live in each cluster's `infrastructure.yaml`.

## Adding an App

```sh
app=myapp
cp -r doc/templates/helm-app kubernetes/apps/$app
sed -i '' "s/APP_NAME/$app/g" kubernetes/apps/$app/*.yaml
```

1. Fill in the chart and `values:` in `helmrelease.yaml`.
2. Encrypt the secret: `sops -e -i kubernetes/apps/$app/secret.sops.yaml`.
3. Add `$app` to `kubernetes/apps/kustomization.yaml`.
4. Open a PR.

> Full guide: [doc/adding-an-app.md](doc/adding-an-app.md).

## Docs

| Doc | Covers |
|---|---|
| [Adding an app](doc/adding-an-app.md) | Helm template, step by step |
| [Operations](doc/operations.md) | health checks, kubeconfig |
| [Workflow](doc/workflow.md) | PRs, CI, commit rules |
| [Networking](doc/networking.md) | VLANs, IPs, certs, tunnel |
| [Storage](doc/storage.md) | Longhorn, NAS backups |
| [Secrets](doc/secrets.md) | sops + age, key recovery |
| [Talos](doc/talos.md) | 1.14 quirks, upgrades |
| [Rebuild](doc/rebuild.md) | disaster recovery |
| [Sure](doc/runbooks/sure.md) | backups, restore, upgrades |

## Thanks and Gratitudes

- [bjw-s helm charts](https://github.com/bjw-s-labs/helm-charts), for app-template
- [homarr-labs/dashboard-icons](https://github.com/homarr-labs/dashboard-icons), for the diagram icons
- [kubesearch.dev](https://kubesearch.dev), for finding how others deploy the same apps

## Contributing

Any contributions you make are **greatly appreciated**.

If you have a suggestion that would make this better, please see [contributing guide](https://github.com/folatulip/homelab?tab=contributing-ov-file#contribution-guidelines) for more information.
Please also read the [code of conduct](https://github.com/folatulip/homelab?tab=coc-ov-file) and [security policy](https://github.com/folatulip/homelab?tab=security-ov-file).
Thanks again!

## Unofficial Wiki

[![DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/folatulip/homelab)

## License

Distributed under the MIT License. See [license page](https://github.com/folatulip/homelab/blob/main/LICENSE) or `LICENSE.txt` for more information.

<!-- SHIELD LINKS -->
[terraform-shield]: https://img.shields.io/badge/Terraform-844FBA?style=for-the-badge&logo=terraform&logoColor=white
[k8s-shield]: https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white
[proxmox-shield]: https://img.shields.io/badge/Proxmox-E57000?style=for-the-badge&logo=proxmox&logoColor=white
[talos-shield]: https://img.shields.io/badge/Talos-e43245?style=for-the-badge&logo=talos&logoColor=white
[flux-shield]: https://img.shields.io/badge/Flux-5468FF?style=for-the-badge&logo=flux&logoColor=white
