#!/usr/bin/env bash

# `SOPS_AGE_KEY` を使って SOPS で暗号化した cluster input を `.secret/cluster-inputs.env` に復号し、
# 後続の Talos artifact 生成で使える状態にそろえる。

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

secrets_dir="${MISTSHIP_SECRETS_DIR:-$repo_root/.secret}"
cluster_inputs_sops_file="${MISTSHIP_CLUSTER_INPUTS_SOPS_FILE:-secrets/mistship/cluster-inputs.sops.env}"
cluster_secrets_sops_file="${MISTSHIP_CLUSTER_SECRETS_SOPS_FILE:-secrets/mistship/cluster-secrets.sops.yaml}"
cluster_env_file="$secrets_dir/cluster-inputs.env"
cluster_secrets_file="${CLUSTER_SECRETS:-$secrets_dir/cluster-secrets.yaml}"

mkdir -p "$secrets_dir/generated" "$secrets_dir/nodes"

if [[ -z "${SOPS_AGE_KEY:-}" ]]; then
  echo "Missing SOPS_AGE_KEY" >&2
  exit 1
fi

if [[ ! -f "$cluster_inputs_sops_file" ]]; then
  echo "Missing SOPS-encrypted cluster inputs: $cluster_inputs_sops_file" >&2
  exit 1
fi

if [[ ! -f "$cluster_secrets_sops_file" ]]; then
  echo "Missing SOPS-encrypted Talos secrets bundle: $cluster_secrets_sops_file" >&2
  exit 1
fi

echo "::group::Decrypt cluster inputs"
sops --decrypt --output "$cluster_env_file" "$cluster_inputs_sops_file"
sops --decrypt --output "$cluster_secrets_file" "$cluster_secrets_sops_file"
chmod 600 "$cluster_env_file" "$cluster_secrets_file"
echo "::endgroup::"
