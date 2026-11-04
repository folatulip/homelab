# Talos 1.14 notes

- Kubelet settings live in the `KubeletConfig` document. Patching `.machine.kubelet` fails with `kubelet config is already set in v1alpha1 config`, and `extraMounts` no longer exists. Host paths for pods go under `/var/mnt` as user volumes.
- Install settings live in `UnattendedInstallConfig`, not `.machine.install`.
- A control plane that runs workloads loses its `NoSchedule` taint and its `exclude-from-external-load-balancers` label (so MetalLB announces from it) through the `KubeNodeConfig` document. `.cluster.allowSchedulingOnControlPlanes` is rejected next to it. The module applies `patches/schedulable-controlplane/` when `allow_scheduling_on_control_planes = true`.
- Talos enforces the `baseline` Pod Security level. Namespaces whose pods need host access (`metallb-system`, `local-path-storage`, `longhorn-system`) are labeled `pod-security.kubernetes.io/enforce: privileged`.
- System extensions are baked into the image. Changing the `extensions` list in `terraform/main.tf` changes the installer image; after `terraform apply`, roll each node with `talosctl -n <ip> upgrade --image "$(terraform -chdir=terraform output -raw installer_image)"`.
- Check a config patch before applying it: `talosctl validate --config <file> --mode metal`.

