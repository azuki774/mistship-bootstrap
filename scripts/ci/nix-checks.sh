#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "::group::Verify toolchain"
command -v talosctl talhelper kubectl kubeconform jq yq sops age
talosctl version --client
talhelper --help >/dev/null
bash -n ./scripts/ops/decrypt-cluster-secrets.sh
bash -n ./scripts/ops/apply-bootstrap-manifests.sh
bash -n ./scripts/check-doc-links.sh
bash -n ./scripts/ops/prepare-cluster-access.sh
bash ./scripts/check-doc-links.sh
echo "::endgroup::"
