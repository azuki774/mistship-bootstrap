#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

secrets_dir="${MISTSHIP_SECRETS_DIR:-$repo_root/.secret}"
rendered_dir="$secrets_dir/rendered"
template_file="manifests/bootstrap/gitops-entry/00-bootstrap-root-application.yaml.tmpl"
argocd_repository_input="$secrets_dir/argocd-repository.yaml"
app_output="$rendered_dir/bootstrap-root-application.yaml"
repository_secret_output="$rendered_dir/argocd-repository-secret.yaml"
repo_name="${ARGOCD_DEPLOY_REPO_NAME:-}"

mkdir -p "$rendered_dir"
rm -f "$app_output" "$repository_secret_output"

if [[ -z "$repo_name" ]]; then
  echo "Skipping GitOps entry render: ARGOCD_DEPLOY_REPO_NAME is not set."
  exit 0
fi

# Update the hardcoded GitHub owner if the private deploy repo moves out of azuki774.
repo_url="git@github.com:azuki774/${repo_name}.git"

sed "s|__ARGOCD_REPO_URL__|$repo_url|g" "$template_file" > "$app_output"

if [[ ! -f "$argocd_repository_input" ]]; then
  echo "Skipping Argo CD repository Secret render: $argocd_repository_input not found."
  exit 0
fi

ssh_private_key="$(yq eval -r '.sshPrivateKey' "$argocd_repository_input")"

if [[ -z "$ssh_private_key" || "$ssh_private_key" == "null" ]]; then
  echo "Missing .sshPrivateKey in $argocd_repository_input" >&2
  exit 1
fi

{
  printf '%s\n' "apiVersion: v1"
  printf '%s\n' "kind: Secret"
  printf '%s\n' "metadata:"
  printf '%s\n' "  name: bootstrap-repository"
  printf '%s\n' "  namespace: argocd"
  printf '%s\n' "  labels:"
  printf '%s\n' "    argocd.argoproj.io/secret-type: repository"
  printf '%s\n' "stringData:"
  printf '%s\n' "  type: git"
  printf '%s\n' "  url: $repo_url"
  printf '%s\n' "  sshPrivateKey: |"
  printf '%s\n' "$ssh_private_key" | sed 's/^/    /'
} > "$repository_secret_output"

chmod 600 "$app_output" "$repository_secret_output"
