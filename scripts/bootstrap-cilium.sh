#!/usr/bin/env bash
# First install of Cilium on a new cluster, before Flux exists.
# Talos boots k8s-geese with no CNI (cni = "none"), so nodes stay NotReady and
# Flux's pods can't start until Cilium is in. After this, bootstrap Flux: its
# HelmRelease (kubernetes/infrastructure/cilium) has the same release name and
# namespace, so it takes over this release instead of installing a new one.
#
# Usage: scripts/bootstrap-cilium.sh <kube-context>   (needs helm and kubectl)
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <kube-context>" >&2
  exit 1
fi
context=$1

# Run from the repo root so the paths below work from anywhere
cd "$(dirname "$0")/.."

CILIUM_DIR=kubernetes/infrastructure/cilium

# Same chart version as the HelmRelease, so Flux doesn't upgrade right after
version=$(sed -n 's/^ *version: *\([0-9][0-9.]*\).*/\1/p' "$CILIUM_DIR/helmrelease.yaml" | head -1)
if [[ -z $version ]]; then
  echo "couldn't read the chart version from $CILIUM_DIR/helmrelease.yaml" >&2
  exit 1
fi

echo "Installing Cilium $version on context '$context'"

# Release name + namespace must match the HelmRelease (cilium in kube-system).
# upgrade --install so running it twice is fine.
helm upgrade --install cilium cilium \
  --repo https://helm.cilium.io \
  --version "$version" \
  --namespace kube-system \
  --values "$CILIUM_DIR/values.yaml" \
  --kube-context "$context" \
  --wait --timeout 10m

# Nodes turn Ready once the Cilium agent runs on them
kubectl --context "$context" wait --for=condition=Ready nodes --all --timeout=10m
kubectl --context "$context" get nodes -o wide

echo "Cilium is up. Next: flux bootstrap github ... --path=kubernetes/cluster"
