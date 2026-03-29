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
  yq eval -e '.patches[0].path == "patch-repo-server-init.yaml"' "$argocd_dir/kustomization.yaml" >/dev/null
  yq eval -e '.apiVersion == "apps/v1"' "$argocd_dir/patch-repo-server-init.yaml" >/dev/null
  yq eval -e '.kind == "Deployment"' "$argocd_dir/patch-repo-server-init.yaml" >/dev/null
  yq eval -e '.metadata.name == "argocd-repo-server"' "$argocd_dir/patch-repo-server-init.yaml" >/dev/null
  yq eval -e '.spec.template.spec.initContainers[0].name == "copyutil"' "$argocd_dir/patch-repo-server-init.yaml" >/dev/null
  yq eval -e '.spec.template.spec.initContainers[0].args[0] == "/bin/cp --update=none /usr/local/bin/argocd /var/run/argocd/argocd && /bin/ln -sfn /var/run/argocd/argocd /var/run/argocd/argocd-cmp-server"' \
    "$argocd_dir/patch-repo-server-init.yaml" >/dev/null
  grep -F 'kubectl --kubeconfig "$KUBECONFIG" apply --server-side -k manifests/bootstrap/argocd' \
    scripts/ops/apply-bootstrap-manifests.sh >/dev/null
fi

echo "Manifest validation passed."
