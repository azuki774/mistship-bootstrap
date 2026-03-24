#!/usr/bin/env bash

set -euo pipefail

delete_mode=0
assume_yes=0

usage() {
  cat <<'EOF'
Usage: cleanup-flannel.sh [--delete] [--yes]

Inventory Flannel-related resources left in the cluster.

Options:
  --delete  Delete the discovered resources after showing the inventory.
  --yes     Skip the confirmation prompt when used with --delete.
  -h, --help
            Show this help.

The script matches resources whose name or namespace contains "flannel".
It targets common Flannel leftovers in kubeadm-style clusters:
DaemonSet, Pod, ConfigMap, ServiceAccount, Role, RoleBinding,
ClusterRole, ClusterRoleBinding, and Namespace.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --delete)
      delete_mode=1
      ;;
    --yes)
      assume_yes=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: $command_name" >&2
    exit 1
  fi
}

require_command kubectl
require_command jq

resource_type_for_kind() {
  case "$1" in
    DaemonSet) echo "daemonset" ;;
    Pod) echo "pod" ;;
    ConfigMap) echo "configmap" ;;
    ServiceAccount) echo "serviceaccount" ;;
    Role) echo "role" ;;
    RoleBinding) echo "rolebinding" ;;
    ClusterRole) echo "clusterrole" ;;
    ClusterRoleBinding) echo "clusterrolebinding" ;;
    Namespace) echo "namespace" ;;
    *)
      echo "Unsupported kind: $1" >&2
      return 1
      ;;
  esac
}

print_section_header() {
  local title="$1"
  printf '\n== %s ==\n' "$title"
}

collect_namespaced_resources() {
  kubectl get daemonset,pod,configmap,serviceaccount,role,rolebinding -A -o json | jq -r '
    .items[]
    | select(
        ((.metadata.name // "") | ascii_downcase | contains("flannel"))
        or
        ((.metadata.namespace // "") | ascii_downcase | contains("flannel"))
      )
    | [.kind, (.metadata.namespace // "-"), .metadata.name]
    | @tsv
  '
}

collect_cluster_resources() {
  kubectl get clusterrole,clusterrolebinding,namespace -o json | jq -r '
    .items[]
    | select(((.metadata.name // "") | ascii_downcase | contains("flannel")))
    | [.kind, "-", .metadata.name]
    | @tsv
  '
}

delete_resource() {
  local kind="$1"
  local namespace="$2"
  local name="$3"
  local resource_type

  resource_type="$(resource_type_for_kind "$kind")"

  if [[ "$resource_type" == "namespace" || "$namespace" == "-" ]]; then
    kubectl delete "$resource_type" "$name" --ignore-not-found
    return 0
  fi

  kubectl delete -n "$namespace" "$resource_type" "$name" --ignore-not-found
}

print_inventory() {
  local items=("$@")

  if [[ "${#items[@]}" -eq 0 ]]; then
    echo "No Flannel-related resources found."
    return 0
  fi

  printf '%-20s %-20s %s\n' "KIND" "NAMESPACE" "NAME"
  printf '%-20s %-20s %s\n' "----" "---------" "----"

  local line
  for line in "${items[@]}"; do
    IFS=$'\t' read -r kind namespace name <<<"$line"
    printf '%-20s %-20s %s\n' "$kind" "$namespace" "$name"
  done
}

mapfile -t discovered_resources < <(
  {
    collect_namespaced_resources
    collect_cluster_resources
  } | sort -u
)

print_section_header "Flannel Inventory"
print_inventory "${discovered_resources[@]}"

if (( delete_mode == 0 )); then
  print_section_header "Next Checks"
  cat <<'EOF'
Run with --delete to remove the discovered resources.

After cleanup, verify:
  kubectl get pods -A -o wide | rg 'flannel|calico'
  kubectl get ds -A
  kubectl -n calico-system get pods -o wide
EOF
  exit 0
fi

if [[ "${#discovered_resources[@]}" -eq 0 ]]; then
  exit 0
fi

if (( assume_yes == 0 )); then
  read -r -p "Delete these resources? [y/N] " reply
  if [[ ! "$reply" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
  fi
fi

print_section_header "Deleting"

deletion_order=(
  "DaemonSet"
  "Pod"
  "ConfigMap"
  "ServiceAccount"
  "RoleBinding"
  "Role"
  "ClusterRoleBinding"
  "ClusterRole"
  "Namespace"
)

for target_kind in "${deletion_order[@]}"; do
  for line in "${discovered_resources[@]}"; do
    IFS=$'\t' read -r kind namespace name <<<"$line"
    if [[ "$kind" != "$target_kind" ]]; then
      continue
    fi

    echo "Deleting $kind $namespace $name"
    delete_resource "$kind" "$namespace" "$name"
  done
done

print_section_header "Post Cleanup"
cat <<'EOF'
Re-run this script without --delete and confirm it reports no Flannel resources.
Then verify the cluster is Calico-only:
  kubectl get pods -A -o wide | rg 'flannel|calico'
  kubectl get ds -A
  kubectl -n calico-system get pods -o wide
EOF
