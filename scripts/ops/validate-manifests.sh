#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

mapfile -t yaml_files < <(find manifests -type f \( -name '*.yaml' -o -name '*.yml' \) ! -name 'README.md' | sort)

if [[ "${#yaml_files[@]}" -eq 0 ]]; then
  echo "No YAML manifests found under manifests/; skipping validation."
  exit 0
fi

for file in "${yaml_files[@]}"; do
  yq eval '.' "$file" >/dev/null
done

calico_dir="manifests/bootstrap/calico"
argocd_dir="manifests/bootstrap/argocd"
gitops_entry_dir="manifests/bootstrap/gitops-entry"
common_patch="patches/common.yaml"

yq eval -e '.cluster.network.cni.name == "none"' "$common_patch" >/dev/null
yq eval -e '.cluster.proxy.disabled == true' "$common_patch" >/dev/null

if [[ ! -d "$calico_dir" ]]; then
  echo "Manifest YAML syntax is valid."
  exit 0
fi

built_in_files=(
  "$calico_dir/00-namespace.yaml" \
  "$calico_dir/20-tigera-operator.yaml"
)

kubeconform -strict -summary "${built_in_files[@]}"

yq eval -e '.apiVersion == "operator.tigera.io/v1"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.kind == "Installation"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.metadata.name == "default"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.variant == "Calico"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.calicoNetwork.linuxDataplane == "BPF"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.calicoNetwork.kubeProxyManagement == "Enabled"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.calicoNetwork.bgp == "Disabled"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.calicoNetwork.ipPools[0].cidr == "10.244.0.0/16"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.calicoNetwork.ipPools[0].encapsulation == "VXLAN"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.calicoNetwork.ipPools[0].natOutgoing == "Enabled"' "$calico_dir/30-installation.yaml" >/dev/null
yq eval -e '.spec.kubeletVolumePluginPath == "None"' "$calico_dir/30-installation.yaml" >/dev/null

yq eval -e '.apiVersion == "operator.tigera.io/v1"' "$calico_dir/31-apiserver.yaml" >/dev/null
yq eval -e '.kind == "APIServer"' "$calico_dir/31-apiserver.yaml" >/dev/null
yq eval -e '.metadata.name == "default"' "$calico_dir/31-apiserver.yaml" >/dev/null
yq eval -e '.spec | length == 0' "$calico_dir/31-apiserver.yaml" >/dev/null

yq eval -e '.apiVersion == "crd.projectcalico.org/v1"' "$calico_dir/32-felixconfiguration.yaml" >/dev/null
yq eval -e '.kind == "FelixConfiguration"' "$calico_dir/32-felixconfiguration.yaml" >/dev/null
yq eval -e '.metadata.name == "default"' "$calico_dir/32-felixconfiguration.yaml" >/dev/null
yq eval -e '.spec.cgroupV2Path == "/sys/fs/cgroup"' "$calico_dir/32-felixconfiguration.yaml" >/dev/null

if [[ -d "$argocd_dir" ]]; then
  kubeconform -strict -summary "$argocd_dir/00-namespace.yaml"
  yq eval -e '.apiVersion == "kustomize.config.k8s.io/v1beta1"' "$argocd_dir/kustomization.yaml" >/dev/null
  yq eval -e '.kind == "Kustomization"' "$argocd_dir/kustomization.yaml" >/dev/null
  yq eval -e '.namespace == "argocd"' "$argocd_dir/kustomization.yaml" >/dev/null
  yq eval -e '.resources[0] == "00-namespace.yaml"' "$argocd_dir/kustomization.yaml" >/dev/null
  yq eval -e '.resources[1] == "https://raw.githubusercontent.com/argoproj/argo-cd/v3.3.4/manifests/install.yaml"' "$argocd_dir/kustomization.yaml" >/dev/null
  grep -F 'kubectl --kubeconfig "$KUBECONFIG" apply --server-side --force-conflicts -k manifests/bootstrap/argocd' \
    scripts/ops/apply-bootstrap-manifests.sh >/dev/null
fi

if [[ -d "$gitops_entry_dir" ]]; then
  yq eval -e '.kind == "ConfigMap"' "$gitops_entry_dir/10-argocd-ssh-known-hosts-cm.yaml" >/dev/null
  yq eval -e '.metadata.name == "argocd-ssh-known-hosts-cm"' \
    "$gitops_entry_dir/10-argocd-ssh-known-hosts-cm.yaml" >/dev/null
  yq eval -e '.data.ssh_known_hosts | test("github\\.com ssh-ed25519")' \
    "$gitops_entry_dir/10-argocd-ssh-known-hosts-cm.yaml" >/dev/null

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  export MISTSHIP_SECRETS_DIR="$tmpdir"
  export ARGOCD_DEPLOY_REPO_NAME="dummy"

  mkdir -p "$tmpdir"
  cp templates/argocd-repository.yaml.example "$tmpdir/argocd-repository.yaml"
  bash ./scripts/render-gitops-entry.sh >/dev/null

  rendered_dir="$tmpdir/rendered"
  yq eval -e '.metadata.name == "bootstrap-root"' \
    "$rendered_dir/bootstrap-root-application.yaml" >/dev/null
  yq eval -e '.spec.source.repoURL == "git@github.com:azuki774/dummy.git"' \
    "$rendered_dir/bootstrap-root-application.yaml" >/dev/null
  yq eval -e '.spec.source.path == "clusters/mistship"' \
    "$rendered_dir/bootstrap-root-application.yaml" >/dev/null
  yq eval -e '.spec.destination.server == "https://kubernetes.default.svc"' \
    "$rendered_dir/bootstrap-root-application.yaml" >/dev/null
  yq eval -e '.stringData.url == "git@github.com:azuki774/dummy.git"' \
    "$rendered_dir/argocd-repository-secret.yaml" >/dev/null
  yq eval -e '.stringData.sshPrivateKey | test("^-----BEGIN OPENSSH PRIVATE KEY-----")' \
    "$rendered_dir/argocd-repository-secret.yaml" >/dev/null

  grep -F 'Skipping optional GitOps entry: ARGOCD_DEPLOY_REPO_NAME is not set.' \
    scripts/ops/apply-bootstrap-manifests.sh >/dev/null
fi

echo "Manifest validation passed."
