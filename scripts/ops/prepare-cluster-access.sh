#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$repo_root"

yaml_single_quote() {
  local value="$1"
  value=${value//\'/\'\"\'\"\'}
  printf "'%s'" "$value"
}

write_tailscale_controlplane_patch() {
  local patch_path="$1"
  local hostname="${TAILSCALE_CONTROLPLANE_HOSTNAME:-${CLUSTER_NAME}-controlplane}"
  local auth_once="${TAILSCALE_CONTROLPLANE_AUTH_ONCE:-true}"
  local accept_dns="${TAILSCALE_CONTROLPLANE_ACCEPT_DNS:-false}"
  local tags="${TAILSCALE_CONTROLPLANE_TAGS:-}"
  local extra_args="${TAILSCALE_CONTROLPLANE_EXTRA_ARGS:-}"
  local combined_extra_args=""

  if [[ -n "$tags" ]]; then
    combined_extra_args="--advertise-tags=$tags"
  fi

  if [[ -n "$extra_args" ]]; then
    if [[ -n "$combined_extra_args" ]]; then
      combined_extra_args+=" "
    fi
    combined_extra_args+="$extra_args"
  fi

  {
    printf '%s\n' '---'
    printf '%s\n' 'apiVersion: v1alpha1'
    printf '%s\n' 'kind: ExtensionServiceConfig'
    printf '%s\n' 'name: tailscale'
    printf '%s\n' 'environment:'
    printf '  - %s\n' "$(yaml_single_quote "TS_AUTHKEY=$TAILSCALE_CONTROLPLANE_AUTHKEY")"
    printf '  - %s\n' "$(yaml_single_quote "TS_AUTH_ONCE=$auth_once")"
    printf '  - %s\n' "$(yaml_single_quote "TS_ACCEPT_DNS=$accept_dns")"
    printf '  - %s\n' "$(yaml_single_quote "TS_HOSTNAME=$hostname")"

    if [[ -n "$combined_extra_args" ]]; then
      printf '  - %s\n' "$(yaml_single_quote "TS_EXTRA_ARGS=$combined_extra_args")"
    fi
  } > "$patch_path"
}

worker_patch_args=()
worker_patch_contents="$(grep -vE "^[[:space:]]*(#|$)" patches/worker.yaml | tr -d "[:space:]" || true)"
if [[ -n "$worker_patch_contents" && "$worker_patch_contents" != "{}" ]]; then
  worker_patch_args+=(--config-patch-worker "@patches/worker.yaml")
fi

controlplane_patch_args=(--config-patch-control-plane "@patches/controlplane.yaml")

if [[ "${TAILSCALE_CONTROLPLANE_ENABLED:-false}" == "true" ]]; then
  if [[ -z "${TAILSCALE_CONTROLPLANE_AUTHKEY:-}" ]]; then
    echo "TAILSCALE_CONTROLPLANE_AUTHKEY is required when TAILSCALE_CONTROLPLANE_ENABLED=true" >&2
    exit 1
  fi

  mkdir -p "$GENERATED_CONFIG_DIR"
  tailscale_controlplane_patch="$GENERATED_CONFIG_DIR/tailscale-controlplane.yaml"
  write_tailscale_controlplane_patch "$tailscale_controlplane_patch"
  controlplane_patch_args+=(--config-patch-control-plane "@$tailscale_controlplane_patch")
fi

echo "::group::Generate Talos artifacts"
talosctl gen config "$CLUSTER_NAME" "https://$CONTROL_PLANE_IP:6443" \
  --with-secrets "$CLUSTER_SECRETS" \
  --install-disk "$INSTALL_DISK" \
  --install-image "$INSTALL_IMAGE" \
  --config-patch "@patches/common.yaml" \
  "${controlplane_patch_args[@]}" \
  "${worker_patch_args[@]}" \
  --output "$GENERATED_CONFIG_DIR"

cp "$GENERATED_CONFIG_DIR/controlplane.yaml" "$CONTROL_PLANE_CONFIG"
cp "$GENERATED_CONFIG_DIR/worker.yaml" "$WORKER_CONFIG"
cp "$GENERATED_CONFIG_DIR/talosconfig" "$TALOSCONFIG"
chmod 600 "$CONTROL_PLANE_CONFIG" "$WORKER_CONFIG" "$TALOSCONFIG"
echo "::endgroup::"

if [[ "${GENERATE_KUBECONFIG:-false}" == "true" ]]; then
  echo "::group::Generate kubeconfig"
  talosctl kubeconfig "$KUBECONFIG" \
    --merge=false \
    --force \
    --talosconfig "$TALOSCONFIG" \
    --endpoints "$CONTROL_PLANE_IP" \
    --nodes "$CONTROL_PLANE_IP"
  chmod 600 "$KUBECONFIG"
  echo "::endgroup::"
fi
