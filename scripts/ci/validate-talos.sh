#!/usr/bin/env bash
# Generate throwaway Talos configs with the same patches Terraform uses
# (terraform/modules/talos-cluster/patches) and run `talosctl validate` on them.
# Catches config the node would reject, e.g. .machine.kubelet next to KubeletConfig.
# Usage: scripts/ci/validate-talos.sh   (needs talosctl and envsubst)
set -euo pipefail
cd "$(dirname "$0")/../.."

PATCHES=terraform/modules/talos-cluster/patches
TALOS_VERSION=$(sed -n 's/.*talos_version *= *"\(v[0-9.]*\)".*/\1/p' terraform/main.tf | head -1)
export installer_image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

args=()
for role in common controlplane worker; do
  for f in $(find "$PATCHES/$role" -name '*.yaml' 2>/dev/null | sort); do
    envsubst '${installer_image}' < "$f" > "$work/$role-$(basename "$f")"
    case $role in
      common) args+=(--config-patch "@$work/$role-$(basename "$f")") ;;
      controlplane) args+=(--config-patch-control-plane "@$work/$role-$(basename "$f")") ;;
      worker) args+=(--config-patch-worker "@$work/$role-$(basename "$f")") ;;
    esac
  done
done

echo "Talos ${TALOS_VERSION}, patches: ${#args[@]}"
talosctl gen config ci-check https://10.0.0.1:6443 \
  --talos-version "${TALOS_VERSION%.*}" "${args[@]}" -o "$work/out" >/dev/null

status=0
for cfg in controlplane worker; do
  talosctl validate --config "$work/out/$cfg.yaml" --mode metal || status=1
done
exit $status
