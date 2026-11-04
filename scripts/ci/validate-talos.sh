#!/usr/bin/env bash
# Generates throwaway Talos configs with the same patches Terraform uses
# (terraform/modules/talos-cluster/patches) and runs `talosctl validate` on them.
# This catches config a node would reject, e.g. .machine.kubelet next to KubeletConfig.
#
# Usage: scripts/ci/validate-talos.sh   (needs talosctl and envsubst)
set -euo pipefail

# Run from the repo root so the paths below work from anywhere
cd "$(dirname "$0")/../.."

PATCHES_DIR=terraform/modules/talos-cluster/patches

# Same Talos version as the cluster, read from terraform/main.tf
TALOS_VERSION=$(sed -n 's/.*talos_version *= *"\(v[0-9.]*\)".*/\1/p' terraform/main.tf | head -1)

# The patches use ${installer_image}, Terraform fills it in, so we do the same with envsubst
export installer_image="ghcr.io/siderolabs/installer:${TALOS_VERSION}"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Which talosctl flag to use for each patch folder.
# data-disk is only on nodes with a Longhorn disk, but we apply it to both
# roles here so it gets validated either way.
patch_flag() {
  case $1 in
    common | data-disk)                     echo "--config-patch" ;;
    controlplane | schedulable-controlplane) echo "--config-patch-control-plane" ;;
    worker)                                  echo "--config-patch-worker" ;;
  esac
}

patch_args=()
for role in common controlplane worker data-disk schedulable-controlplane; do
  # Not every role has a folder
  if [[ ! -d "$PATCHES_DIR/$role" ]]; then
    continue
  fi

  while IFS= read -r patch; do
    rendered="$work_dir/$role-$(basename "$patch")"
    envsubst '${installer_image}' < "$patch" > "$rendered"
    patch_args+=("$(patch_flag "$role")" "@$rendered")
  done < <(find "$PATCHES_DIR/$role" -name '*.yaml' | sort)
done

echo "Talos ${TALOS_VERSION}, $(( ${#patch_args[@]} / 2 )) patches"

# gen config wants the minor version only (v1.14.4 -> v1.14)
talosctl gen config ci-check https://10.0.0.1:6443 \
  --talos-version "${TALOS_VERSION%.*}" \
  "${patch_args[@]}" \
  -o "$work_dir/out" > /dev/null

failed=0
for node_type in controlplane worker; do
  if ! talosctl validate --config "$work_dir/out/$node_type.yaml" --mode metal; then
    failed=1
  fi
done

exit $failed
