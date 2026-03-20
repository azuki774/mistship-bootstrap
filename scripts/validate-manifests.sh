#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mapfile -t yaml_files < <(find manifests -type f \( -name '*.yaml' -o -name '*.yml' \) ! -name 'README.md' | sort)

if [[ "${#yaml_files[@]}" -eq 0 ]]; then
  echo "No YAML manifests found under manifests/; skipping validation."
  exit 0
fi

for file in "${yaml_files[@]}"; do
  yq eval '.' "$file" >/dev/null
done

calico_dir="manifests/infra/calico"

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

echo "Manifest validation passed."
