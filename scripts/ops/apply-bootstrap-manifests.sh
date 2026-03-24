#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

: "${KUBECONFIG:?Set KUBECONFIG before applying bootstrap manifests.}"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "Missing kubeconfig: $KUBECONFIG" >&2
  exit 1
fi

echo "::group::Apply Calico"
./scripts/ops/apply-calico.sh
echo "::endgroup::"

echo "::group::Apply Argo CD bootstrap manifest"
# Argo CD bundles large CRDs, so use server-side apply to avoid
# exceeding the last-applied-configuration annotation limit. Force conflicts
# so bootstrap can take ownership from previous client-side apply runs.
kubectl --kubeconfig "$KUBECONFIG" apply --server-side --force-conflicts -k manifests/bootstrap/argocd
echo "::endgroup::"

echo "::group::Apply optional GitOps entry"
if [[ -z "${ARGOCD_DEPLOY_REPO_NAME:-}" ]]; then
  echo "Skipping optional GitOps entry: ARGOCD_DEPLOY_REPO_NAME is not set."
else
  kubectl --kubeconfig "$KUBECONFIG" wait \
    --for=condition=Established \
    --timeout=120s \
    crd/applications.argoproj.io
  ./scripts/render-gitops-entry.sh

  rendered_dir="${MISTSHIP_SECRETS_DIR:-$repo_root/.secret}/rendered"
  rendered_application="$rendered_dir/bootstrap-root-application.yaml"
  rendered_repository_secret="$rendered_dir/argocd-repository-secret.yaml"

  if [[ ! -f "$rendered_repository_secret" ]]; then
    echo "Skipping optional GitOps entry: missing decrypted SSH deploy key."
  else
    kubectl --kubeconfig "$KUBECONFIG" apply --server-side --force-conflicts \
      -f manifests/bootstrap/gitops-entry/10-argocd-ssh-known-hosts-cm.yaml
    kubectl --kubeconfig "$KUBECONFIG" apply --server-side --force-conflicts \
      -f "$rendered_repository_secret"
    kubectl --kubeconfig "$KUBECONFIG" apply --server-side --force-conflicts \
      -f "$rendered_application"
  fi
fi
echo "::endgroup::"

if [[ -d manifests/bootstrap/ebpf-demo ]]; then
  echo "Skipping optional example manifests under manifests/bootstrap/ebpf-demo."
fi
