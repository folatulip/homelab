#!/usr/bin/env bash
# Render every kustomization Flux applies and validate the output with
# kubeconform. CRD-based objects (Flux, MetalLB, ...) are checked against the
# community CRD schema catalog.
# Usage: scripts/ci/validate-kubernetes.sh   (needs kubectl and kubeconform)
set -euo pipefail
cd "$(dirname "$0")/../.."

CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
# CRD definitions come verbatim from pinned upstream releases and kubeconform
# has no schema for the CRD kind itself, so skip them; the objects that *use*
# those CRDs are still validated.
kubeconform_args=(-strict -summary -skip CustomResourceDefinition -schema-location default -schema-location "$CRD_SCHEMAS")

status=0

# sops-encrypted Secrets carry a top-level `sops:` metadata block that strict
# schemas reject. Flux removes it when decrypting, so drop it before validating.
strip_sops() { awk '/^sops:/{skip=1; next} skip && /^([^ ]|---)/{skip=0} !skip'; }

# Every *.sops.yaml must actually be encrypted (catches a forgotten `sops -e`).
while IFS= read -r f; do
  if ! grep -q '^sops:' "$f" || ! grep -q '^    mac: ENC\[' "$f"; then
    echo "::error file=$f::$f is not sops-encrypted (run: sops -e -i $f)"
    status=1
  fi
done < <(find kubernetes -name '*.sops.yaml' -o -name '*.sops.yml' | sort)

# Folders with a kustomization.yaml: render, then validate.
while IFS= read -r k; do
  dir=$(dirname "$k")
  echo "::group::kustomize $dir"
  if ! kubectl kustomize "$dir" | strip_sops | kubeconform "${kubeconform_args[@]}" -; then
    echo "::error file=$k::$dir failed validation"
    status=1
  fi
  echo "::endgroup::"
done < <(find kubernetes -name kustomization.yaml -not -path '*/flux-system/*' | sort)

# Flux entry point (plain manifests, no kustomization.yaml of ours).
echo "::group::kubernetes/clusters"
if ! find kubernetes/clusters -name '*.yaml' -not -path '*/flux-system/*' -print0 |
  xargs -0 kubeconform "${kubeconform_args[@]}"; then
  echo "::error::kubernetes/clusters failed validation"
  status=1
fi
echo "::endgroup::"

exit $status
