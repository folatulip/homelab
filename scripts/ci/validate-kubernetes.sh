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

# Folders with a kustomization.yaml: render, then validate.
while IFS= read -r k; do
  dir=$(dirname "$k")
  echo "::group::kustomize $dir"
  if ! kubectl kustomize "$dir" | kubeconform "${kubeconform_args[@]}" -; then
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
