#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

: "${KUBECONFIG:?Set KUBECONFIG before applying bootstrap manifests.}"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "Missing kubeconfig: $KUBECONFIG" >&2
  exit 1
fi

echo "::group::Apply Calico"
./scripts/apply-calico.sh
echo "::endgroup::"

echo "::group::Apply Argo CD bootstrap manifest"
# Argo CD bundles large CRDs, so use server-side apply to avoid
# exceeding the last-applied-configuration annotation limit. Force conflicts
# so bootstrap can take ownership from previous client-side apply runs.
kubectl --kubeconfig "$KUBECONFIG" apply --server-side --force-conflicts -k manifests/bootstrap/argocd
echo "::endgroup::"

if [[ -d manifests/bootstrap/ebpf-demo ]]; then
  echo "Skipping optional example manifests under manifests/bootstrap/ebpf-demo."
fi
