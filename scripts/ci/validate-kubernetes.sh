#!/usr/bin/env bash
# Renders every kustomization that Flux applies and validates the output with
# kubeconform. Objects that use CRDs (Flux, Cilium, ...) are checked against
# the community CRD schema catalog.
#
# Usage: scripts/ci/validate-kubernetes.sh   (needs kubectl and kubeconform)
set -euo pipefail

# Run from the repo root so the paths below work from anywhere
cd "$(dirname "$0")/../.."

CRD_SCHEMAS="https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"

# CustomResourceDefinitions are skipped: they come straight from pinned
# upstream releases and kubeconform has no schema for them anyway.
# The objects that *use* those CRDs are still validated.
KUBECONFORM_ARGS=(
  -strict
  -summary
  -skip CustomResourceDefinition
  -schema-location default
  -schema-location "$CRD_SCHEMAS"
)

failed=0

# sops-encrypted Secrets have a top-level `sops:` block that the strict schema
# rejects. Flux removes it when it decrypts, so we remove it too before validating.
strip_sops_metadata() {
  awk '
    /^sops:/              { skipping = 1; next }
    skipping && /^[^ ]/   { skipping = 0 }
    !skipping
  '
}

# 1. Every *.sops.yaml file should actually be encrypted (catches a forgotten `sops -e`)
check_sops_files() {
  local file
  while IFS= read -r file; do
    if ! grep -q '^sops:' "$file" || ! grep -q '^    mac: ENC\[' "$file"; then
      echo "::error file=$file::$file is not sops-encrypted (run: sops -e -i $file)"
      failed=1
    fi
  done < <(find kubernetes \( -name '*.sops.yaml' -o -name '*.sops.yml' \) | sort)
}

# Renders a kustomization, trying up to 3 times. Some of them pull an upstream
# manifest over the network (local-path-provisioner), which can time out.
render() {
  local dir=$1 attempt
  for attempt in 1 2 3; do
    if kubectl kustomize "$dir"; then
      return 0
    fi
    echo "::warning::kubectl kustomize $dir failed (attempt $attempt/3)" >&2
    if [[ $attempt -lt 3 ]]; then
      sleep $((attempt * 5))
    fi
  done
  return 1
}

# 2. Render each folder that has a kustomization.yaml, then validate it
check_kustomizations() {
  local kustomization dir rendered
  while IFS= read -r kustomization; do
    dir=$(dirname "$kustomization")

    echo "::group::kustomize $dir"
    # Render first, so a failed attempt doesn't send half a manifest to kubeconform
    if ! rendered=$(render "$dir") ||
      ! strip_sops_metadata <<< "$rendered" | kubeconform "${KUBECONFORM_ARGS[@]}" -; then
      echo "::error file=$kustomization::$dir failed validation"
      failed=1
    fi
    echo "::endgroup::"
  done < <(find kubernetes -name kustomization.yaml -not -path '*/flux-system/*' | sort)
}

# 3. kubernetes/cluster is
#    the Flux entry points. They're plain manifests (no kustomization.yaml of
#    ours), so validate the files directly.
check_flux_entrypoint() {
  local entry
  for entry in kubernetes/cluster; do
    echo "::group::$entry"
    if ! find "$entry" -name '*.yaml' -not -path '*/flux-system/*' -print0 |
      xargs -0 kubeconform "${KUBECONFORM_ARGS[@]}"; then
      echo "::error::$entry failed validation"
      failed=1
    fi
    echo "::endgroup::"
  done
}

check_sops_files
check_kustomizations
check_flux_entrypoint

exit $failed
