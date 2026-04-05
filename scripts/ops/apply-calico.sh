#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
calico_dir="$repo_root/manifests/bootstrap/calico"
kubernetes_service_host=""
kubernetes_service_port=""
operator_deployment_exists=0

dump_tigera_operator_diagnostics() {
  kubectl get pods -n tigera-operator -o wide || true
  kubectl describe deployment/tigera-operator -n tigera-operator || true
  kubectl logs deployment/tigera-operator -n tigera-operator --tail=200 || true
}

dump_namespace_diagnostics() {
  local namespace="$1"
  local pod
  local logs_found=0

  kubectl get all -n "$namespace" -o wide || true
  kubectl get pods -n "$namespace" -o wide || true
  kubectl get events -n "$namespace" --sort-by=.metadata.creationTimestamp || true
  kubectl describe pods -n "$namespace" || true

  while IFS= read -r pod; do
    logs_found=1
    kubectl logs -n "$namespace" "$pod" --all-containers=true --tail=200 --prefix=true || true
  done < <(kubectl get pods -n "$namespace" -o name 2>/dev/null)

  if (( logs_found == 0 )); then
    echo "No pods found in namespace $namespace for log collection." >&2
  fi
}

rollout_status_or_dump() {
  local kind="$1"
  local name="$2"
  local namespace="$3"
  local timeout="$4"

  if ! kubectl rollout status "$kind/$name" -n "$namespace" --timeout="$timeout"; then
    echo "Rollout failed for $kind/$name in namespace $namespace." >&2
    kubectl describe "$kind/$name" -n "$namespace" || true
    dump_namespace_diagnostics "$namespace"
    return 1
  fi
}

resolve_kubernetes_api_endpoint() {
  local server authority endpoint_host endpoint_port

  if [[ -n "${CALICO_KUBERNETES_SERVICE_HOST:-}" ]]; then
    kubernetes_service_host="$CALICO_KUBERNETES_SERVICE_HOST"
    kubernetes_service_port="${CALICO_KUBERNETES_SERVICE_PORT:-6443}"
    return 0
  fi

  endpoint_host="$(kubectl get endpointslices.discovery.k8s.io \
    -n default \
    -l kubernetes.io/service-name=kubernetes \
    -o jsonpath='{.items[0].endpoints[0].addresses[0]}' 2>/dev/null || true)"
  endpoint_port="$(kubectl get endpointslices.discovery.k8s.io \
    -n default \
    -l kubernetes.io/service-name=kubernetes \
    -o jsonpath='{.items[0].ports[0].port}' 2>/dev/null || true)"

  if [[ -n "$endpoint_host" ]]; then
    kubernetes_service_host="$endpoint_host"
    kubernetes_service_port="${endpoint_port:-6443}"
    return 0
  fi

  server="$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')"
  if [[ -z "$server" ]]; then
    echo "Unable to determine Kubernetes API server from kubeconfig." >&2
    return 1
  fi

  authority="${server#*://}"
  authority="${authority%%/*}"

  if [[ "$authority" == *:* ]]; then
    kubernetes_service_host="${authority%%:*}"
    kubernetes_service_port="${authority##*:}"
  else
    kubernetes_service_host="$authority"
    kubernetes_service_port="443"
  fi
}

apply_kubernetes_services_endpoint_configmap() {
  resolve_kubernetes_api_endpoint

  kubectl create configmap kubernetes-services-endpoint \
    -n tigera-operator \
    --from-literal=KUBERNETES_SERVICE_HOST="$kubernetes_service_host" \
    --from-literal=KUBERNETES_SERVICE_PORT="$kubernetes_service_port" \
    --dry-run=client \
    -o yaml | kubectl apply -f -
}

wait_for_crd() {
  local crd_name="$1"
  local timeout_seconds="${2:-120}"
  local deadline=$((SECONDS + timeout_seconds))

  until kubectl get crd "$crd_name" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for CRD $crd_name to be created." >&2
      dump_tigera_operator_diagnostics
      return 1
    fi
    sleep 2
  done

  kubectl wait --for=condition=Established "crd/$crd_name" --timeout="${timeout_seconds}s"
}

wait_for_namespace() {
  local namespace="$1"
  local timeout_seconds="${2:-120}"
  local deadline=$((SECONDS + timeout_seconds))

  until kubectl get namespace "$namespace" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for namespace $namespace to be created." >&2
      return 1
    fi
    sleep 2
  done
}

wait_for_workload() {
  local kind="$1"
  local name="$2"
  local namespace="$3"
  local timeout_seconds="${4:-180}"
  local deadline=$((SECONDS + timeout_seconds))

  until kubectl get "$kind/$name" -n "$namespace" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      echo "Timed out waiting for $kind/$name in namespace $namespace to be created." >&2
      dump_namespace_diagnostics "$namespace"
      return 1
    fi
    sleep 2
  done
}

if [[ ! -d "$calico_dir" ]]; then
  echo "No Calico manifests found under $calico_dir; skipping Calico apply."
  exit 0
fi

kubectl apply -f "$calico_dir/00-namespace.yaml"

if kubectl get deployment/tigera-operator -n tigera-operator >/dev/null 2>&1; then
  operator_deployment_exists=1
fi

apply_kubernetes_services_endpoint_configmap
kubectl apply -f "$calico_dir/20-tigera-operator.yaml"

if (( operator_deployment_exists == 1 )); then
  kubectl rollout restart deployment/tigera-operator -n tigera-operator
fi

kubectl rollout status deployment/tigera-operator -n tigera-operator --timeout=5m

wait_for_crd installations.operator.tigera.io
wait_for_crd apiservers.operator.tigera.io
wait_for_crd felixconfigurations.crd.projectcalico.org
wait_for_crd tigerastatuses.operator.tigera.io

kubectl apply -f "$calico_dir/30-installation.yaml"
kubectl apply -f "$calico_dir/31-apiserver.yaml"
kubectl apply -f "$calico_dir/32-felixconfiguration.yaml"

wait_for_namespace calico-system
wait_for_workload deployment calico-kube-controllers calico-system
rollout_status_or_dump deployment calico-kube-controllers calico-system 10m
wait_for_workload daemonset calico-node calico-system
rollout_status_or_dump daemonset calico-node calico-system 10m
wait_for_workload deployment calico-apiserver calico-system
rollout_status_or_dump deployment calico-apiserver calico-system 10m

kubectl get tigerastatus
