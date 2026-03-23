# TalOS コントロールプレーン起動手順

この文書は、local operator が TalOS の control plane を bootstrap し、GitOps bootstrap 前の状態まで持っていくための手順です。

対象:

- TalOS イメージ書き込みまでは完了している
- control plane ノードは maintenance mode で起動している
- 暗号化済み cluster input は `secrets/mistship/` にある
- 平文 secret や実運用の inventory は Git の外にある

この repo は local bootstrap 用です。CI/CD からクラスタを操作する前提はありません。

## 前提

ローカルでは `devShell` を使います。

```bash
nix develop
```

復号前は `.secret/` が空でも構いません。必要な平文はこの手順の途中で生成します。

必要な入力値は [templates/cluster-inputs.env.example](../templates/cluster-inputs.env.example) を参照してください。

## 1. SOPS 暗号化 input を復号する

まず `SOPS_AGE_KEY` を export し、cluster input を `.secret/` に復号します。

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
bash ./scripts/decrypt-cluster-secrets.sh
```

続いて環境変数を読み込みます。

```bash
set -a
source .secret/cluster-inputs.env
set +a
```

ここで使うファイル:

- `secrets/mistship/cluster-inputs.sops.env`
- `secrets/mistship/cluster-secrets.sops.yaml`
- `.secret/cluster-inputs.env`
- `.secret/cluster-secrets.yaml`

SOPS 管理の境界は [docs/secrets.md](secrets.md) を参照してください。

## 2. TalOS 用の生成物を作る

`prepare-cluster-access.sh` は、復号済み input と `patches/*.yaml` から次を生成します。

- `talosconfig`
- `controlplane.yaml`
- `worker.yaml`

```bash
bash ./scripts/prepare-cluster-access.sh
```

この repo では `image.yml` の schematic に合わせた installer image を使うため、`INSTALL_IMAGE` を明示します。`patches/common.yaml` では次の前提を固定しています。

- `machine.network.kubespan.enabled: true`
- `machine.network.kubespan.advertiseKubernetesNetworks: false`
- `cluster.network.cni.name: none`
- `cluster.proxy.disabled: true`

生成後の想定配置:

```text
.secret/
├── cluster-inputs.env
├── cluster-secrets.yaml
├── generated/
│   ├── controlplane.yaml
│   ├── worker.yaml
│   └── talosconfig
├── nodes/
│   ├── controlplane.yaml
│   └── worker.yaml
└── talosconfig
```

## 3. maintenance mode のノードへ config を適用する

control plane ノードに `--insecure` で接続できることを確認します。

```bash
talosctl version --insecure --nodes "$CONTROL_PLANE_IP"
talosctl get disks --insecure --nodes "$CONTROL_PLANE_IP"
```

その後、生成済み `controlplane.yaml` を適用します。

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
```

maintenance mode を抜けたら、通常の TalOS API 接続へ切り替えて確認します。

```bash
talosctl version \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

## 4. etcd / Kubernetes control plane を bootstrap する

single-node control plane でも `talosctl bootstrap` は 1 回だけ実行します。

```bash
talosctl bootstrap \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

bootstrap 後は `etcd` と static pod の状態を確認します。

```bash
talosctl service etcd \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"

talosctl etcd members \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"

talosctl get staticpods \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

主に確認するもの:

- `etcd` が `Running`
- `kube-apiserver`
- `kube-controller-manager`
- `kube-scheduler`

## 5. `kubeconfig` を取得する

Kubernetes API が応答するようになったら、同じ入力値から `kubeconfig` を生成します。

```bash
GENERATE_KUBECONFIG=true bash ./scripts/prepare-cluster-access.sh
```

疎通確認:

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A
```

## 6. GitOps bootstrap へ進む

TalOS control plane と `kubeconfig` がそろったら、この repo の次の責務は Calico と Argo CD の導入です。

- [docs/gitops-bootstrap.md](gitops-bootstrap.md)
- [manifests/infra/README.md](../manifests/infra/README.md)

worker を追加する場合は、同じ `.secret/cluster-secrets.yaml` から生成した `worker.yaml` を `apply-config --insecure` で適用します。worker の再参加後も継続反映は Argo CD 側へ渡します。
