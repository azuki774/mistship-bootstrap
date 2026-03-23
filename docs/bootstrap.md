# TalOS Bootstrap

`mistship-bootstrap` で TalOS の control plane を立ち上げるまでの最短手順です。前提は、node が maintenance mode で起動しており、SOPS 暗号化済み input が現行 path の `secrets/mistship/` にあることです。

## 1. 入力を復号する

```bash
nix develop
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
bash ./scripts/decrypt-cluster-secrets.sh
set -a
source .secret/cluster-inputs.env
set +a
```

## 2. TalOS 用ファイルを作る

```bash
bash ./scripts/prepare-cluster-access.sh
```

これで主に次が生成されます。

- `.secret/talosconfig`
- `.secret/nodes/controlplane.yaml`
- `.secret/nodes/worker.yaml`

control plane を Tailscale に参加させる場合は、`cluster-inputs.env` に `TAILSCALE_CONTROLPLANE_*` を入れたうえで同じ script を使います。
詳細は [docs/tailscale.md](tailscale.md) を参照してください。

## 3. control plane に適用する

```bash
talosctl version --insecure --nodes "$CONTROL_PLANE_IP"
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
```

maintenance mode を抜けたら通常接続で確認します。

```bash
talosctl version \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

## 4. bootstrap する

```bash
talosctl bootstrap \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

確認例:

```bash
talosctl service etcd \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"

talosctl get staticpods \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

## 5. kubeconfig を取る

```bash
GENERATE_KUBECONFIG=true bash ./scripts/prepare-cluster-access.sh
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
```

ここまで終わったら次へ進みます。

- [docs/gitops-bootstrap.md](gitops-bootstrap.md)
- [manifests/bootstrap/README.md](../manifests/bootstrap/README.md)
