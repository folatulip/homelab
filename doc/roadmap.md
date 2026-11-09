# Roadmap

## 1. Cleanup

- [ ] Rename nodes `goose` / `goose2` to `goose-s1-pve` / `goose-s2-pve`
- [x] Restructure the `kubernetes/` folder so it's easier to follow
- [ ] Migrate services to Helm
- [ ] Improve the docs

## 2. CI + local workflow

- [ ] Terraform checks in CI (`fmt`, `validate`, `tflint`, `plan`)
- [ ] Secret scanning with gitleaks + secrets rotation and notification
- [ ] Local checks before commit (same checks as CI)
- [ ] PR template tied into the CI checks

## 3. One cluster

Design and migration order: [ADR 0001](adr/0001-single-cluster-cilium.md).

- [x] Integrating Cilium
- [x] Merge the trusted + DMZ clusters into one
- [x] Handle VLANs inside the cluster (node pools per VLAN + network policies)

## 4. Terraform the rest

- [ ] Proxmox Backup Server

## 5. Move LXCs to Kubernetes

- [ ] Migrate every LXC on Proxmox into the cluster
- [ ] Remove the old LXCs

## 6. Monitoring

- [x] Prometheus + Grafana
- [ ] Alertmanager
- [ ] Offsite Uptime Kuma (still alerts if the whole lab is down)
- [ ] README badges integration with Prometheus via a cron job

## 7. Backups

- [ ] 3-2-1 backups
- [ ] Encrypt sensitive data at rest and offsite

## 8. Offsite third node

- [ ] Talos KubeSpan OR Site-to-site VPN
- [ ] Proxmox management access across sites
- [ ] Terraform support for a second site
- [ ] Join it to Kubernetes (control plane for HA)

## N. Others

- [ ] OAuth in front of every dmz apps
- [ ] Pen testing automation
- [ ] GitHub self-hosted runner accross sites with Tailscale for terraform apply/plan

## Ongoing

- [ ] Redeploy drill: rebuild everything from the repo, then update the docs with what broke
