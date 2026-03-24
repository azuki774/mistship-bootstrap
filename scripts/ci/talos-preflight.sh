#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

echo "::group::Validate manifests"
bash ./scripts/ops/validate-manifests.sh
echo "::endgroup::"

echo "::group::Validate docs"
bash ./scripts/check-doc-links.sh
echo "::endgroup::"

echo "::group::Validate shell scripts"
bash -n ./scripts/ops/apply-bootstrap-manifests.sh
bash -n ./scripts/check-doc-links.sh
bash -n ./scripts/ops/decrypt-cluster-secrets.sh
bash -n ./scripts/ops/prepare-cluster-access.sh
bash -n ./scripts/render-gitops-entry.sh
echo "::endgroup::"

echo "::group::Validate Talos patches"
patch_files=(
  "patches/common.yaml"
  "patches/controlplane.yaml"
  "patches/worker.yaml"
)

for file in "${patch_files[@]}"; do
  yq eval '.' "$file" >/dev/null
done

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# These synthetic values are only for offline config generation in CI.
# This check does not contact the real cluster or validate environment-specific inputs.
export MISTSHIP_SECRETS_DIR="$tmpdir"
export CLUSTER_SECRETS="$tmpdir/cluster-secrets.yaml"
export TALOSCONFIG="$tmpdir/talosconfig"
export KUBECONFIG="$tmpdir/kubeconfig"
export GENERATED_CONFIG_DIR="$tmpdir/generated"
export CONTROL_PLANE_CONFIG="$tmpdir/nodes/controlplane.yaml"
export WORKER_CONFIG="$tmpdir/nodes/worker.yaml"
export CLUSTER_NAME="mistship-ci-dummy"
export CONTROL_PLANE_IP="192.0.2.11"
export INSTALL_DISK="$(yq eval -r '.machine.install.disk' patches/common.yaml)"
export INSTALL_IMAGE="$(yq eval -r '.machine.install.image' patches/common.yaml)"
export TAILSCALE_CONTROLPLANE_ENABLED="true"
export TAILSCALE_CONTROLPLANE_AUTHKEY="tskey-ci-dummy"
export TAILSCALE_CONTROLPLANE_HOSTNAME="mistship-ci-controlplane"
export TAILSCALE_CONTROLPLANE_TAGS="tag:mistship-controlplane"
export TAILSCALE_CONTROLPLANE_AUTH_ONCE="true"
export TAILSCALE_CONTROLPLANE_ACCEPT_DNS="false"

mkdir -p "$GENERATED_CONFIG_DIR" "$tmpdir/nodes"

talosctl gen secrets -o "$CLUSTER_SECRETS"
bash ./scripts/ops/prepare-cluster-access.sh

test -s "$CONTROL_PLANE_CONFIG"
test -s "$WORKER_CONFIG"
test -s "$TALOSCONFIG"
grep -q 'kind: ExtensionServiceConfig' "$CONTROL_PLANE_CONFIG"
grep -q 'name: tailscale' "$CONTROL_PLANE_CONFIG"

echo "Patch validation passed."
echo "::endgroup::"
