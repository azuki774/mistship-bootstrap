# TalOS コントロールプレーン起動手順

この手順は、TalOS ノードが maintenance mode で起動しており、そこから Kubernetes の control plane を立ち上げるためのものです。

対象:

- TalOS のイメージ書き込みまでは完了している
- control plane ノードはまだクラスタ参加前で、TalOS API に `--insecure` で接続できる
- 実 IP、実ホスト名、秘密情報は Git の外にある

この手順では、TalOS v1.12 系を前提にしています。

## 事前準備

ローカルではこのリポジトリの `devShell` を使います。

```bash
nix develop
```

開始時点では、最低限以下だけあれば進められます。

```text
.secret/
└── .gitkeep
```

補足:

- `controlplane.yaml` と `talosconfig` はこの手順の途中で生成する
- `kubeconfig` は Kubernetes API 起動後に取得する

## 変数を決める

このリポジトリには `.env.example` を置き、ローカル専用の `.env` は Git へ含めません。

まず `.env` を読み込みます。

```bash
source .env
```

`.env` には最低限、以下を入れます。

```bash
MISTSHIP_SECRETS_DIR=.secret
TALOSCONFIG="$MISTSHIP_SECRETS_DIR/talosconfig"
KUBECONFIG="$MISTSHIP_SECRETS_DIR/kubeconfig"
CLUSTER_SECRETS="$MISTSHIP_SECRETS_DIR/cluster-secrets.yaml"
GENERATED_CONFIG_DIR="$MISTSHIP_SECRETS_DIR/generated"
CLUSTER_NAME=mistship
INSTALL_DISK=/dev/sda
TALOS_VERSION=v1.12.6
SCHEMATIC_ID=077514df2c1b6436460bc60faabc976687b16193b8a1290fda4366c69024fec2
INSTALL_IMAGE="factory.talos.dev/installer/$SCHEMATIC_ID:$TALOS_VERSION"
CONTROL_PLANE_IP=192.0.2.11
CONTROL_PLANE_CONFIG="$MISTSHIP_SECRETS_DIR/nodes/controlplane.yaml"
WORKER_CONFIG="$MISTSHIP_SECRETS_DIR/nodes/worker.yaml"
```

`.secret` 配下は Git に含めず、`.secret/.gitkeep` だけを置きます。

TalOS API の endpoint には control plane ノードの実 IP を使います。VIP や Kubernetes API 用の LB は使いません。
`INSTALL_IMAGE` は [`image.yml`](/home/azuki/work/mistship/image.yml) の schematic と TalOS バージョンに合わせます。

## 0.5. secret と public を分ける

TalOS の生成物は、そのままだと secret と public が同じファイルに混ざります。

このリポジトリでは次のように分けます。

- Git に載せる: [`image.yml`](/home/azuki/work/mistship/image.yml)、[`patches/common.yaml`](/home/azuki/work/mistship/patches/common.yaml)、[`patches/controlplane.yaml`](/home/azuki/work/mistship/patches/controlplane.yaml)、[`patches/worker.yaml`](/home/azuki/work/mistship/patches/worker.yaml)
- Git に載せない: `cluster-secrets.yaml`、`talosconfig`、`kubeconfig`、生成済みの `controlplane.yaml`、`worker.yaml`

`patches/*.yaml` には公開可能な設定だけを書き、secret は `cluster-secrets.yaml` に閉じ込めます。

## 1. maintenance mode に接続できることを確認する

まず control plane ノードに `--insecure` で接続できることを確認します。

```bash
talosctl version --insecure --nodes "$CONTROL_PLANE_IP"
```

必要なら console でも maintenance mode であることを確認します。

確認しておくとよい項目:

- 期待した TalOS バージョンで起動している
- NIC が認識され、IP が付与されている
- インストール先ディスクが見えている

ディスク確認例:

```bash
talosctl get disks --insecure --nodes "$CONTROL_PLANE_IP"
```

`apply-config` の前に、cluster secrets、`controlplane.yaml`、`worker.yaml`、`talosconfig` をローカルへ生成しておく必要があります。

## 2. secrets と machine config を生成する

single-node control plane では、Kubernetes API endpoint に control plane 自身の `https://<IP>:6443` を使います。
`talosctl gen config` 自体は `--install-disk` と `--install-image` を省略しても動きます。

- `--install-disk`: 省略時の既定値は `/dev/sda`
- `--install-image`: 省略時の既定値は Talos 標準 installer image

ただし、このリポジトリでは `image.yml` で system extension を使っているため、`--install-image` は明示します。これを省くと、インストール後のディスク上の TalOS に extension が入りません。

`--install-disk` は環境によって `vda` や `nvme0n1` になるので、誤爆を避けるため明示します。

公開可能な差分は `patches/*.yaml` に寄せ、secret は `talosctl gen secrets` の出力に閉じ込めます。

```bash
talosctl gen secrets -o "$CLUSTER_SECRETS"

talosctl gen config "$CLUSTER_NAME" "https://$CONTROL_PLANE_IP:6443" \
  --with-secrets "$CLUSTER_SECRETS" \
  --install-disk "$INSTALL_DISK" \
  --install-image "$INSTALL_IMAGE" \
  --config-patch "@patches/common.yaml" \
  --config-patch-control-plane "@patches/controlplane.yaml" \
  --output "$GENERATED_CONFIG_DIR"
  # --config-patch-worker "@patches/worker.yaml" \

cp "$GENERATED_CONFIG_DIR/controlplane.yaml" "$CONTROL_PLANE_CONFIG"
cp "$GENERATED_CONFIG_DIR/worker.yaml" "$WORKER_CONFIG"
cp "$GENERATED_CONFIG_DIR/talosconfig" "$TALOSCONFIG"
```

ここで生成されるもの:

- `"$CLUSTER_SECRETS"`: TalOS / Kubernetes の secret bundle
- `"$CONTROL_PLANE_CONFIG"`: control plane 用 machine config
- `"$WORKER_CONFIG"`: worker 用 machine config
- `"$TALOSCONFIG"`: `talosctl` で使うクライアント設定

生成後の想定配置:

```text
.secret/
├── cluster-secrets.yaml
├── talosconfig
├── generated/
│   ├── controlplane.yaml
│   ├── worker.yaml
│   └── talosconfig
└── nodes/
    ├── controlplane.yaml
    └── worker.yaml
```

この構成にしておくと、公開可能な設定変更は主に `patches/*.yaml` に集約できます。

必要なら生成直後に endpoint もそろえます。

```bash
talosctl config endpoint "$CONTROL_PLANE_IP" --talosconfig "$TALOSCONFIG"
talosctl config node "$CONTROL_PLANE_IP" --talosconfig "$TALOSCONFIG"
```

## 3. control plane ノードへ machine config を適用する

maintenance mode のノードには `apply-config --insecure` で machine config を流し込みます。

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
```

適用後、ノードは再構成されて maintenance mode を抜けます。数十秒から数分待って TalOS API に通常接続できることを確認します。

```bash
talosctl version \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

ここで失敗する場合は、machine config の内容かネットワーク定義が誤っています。maintenance mode に戻っているなら、設定が起動条件を満たしていません。

## 4. control plane の bootstrap を 1 回だけ実行する

single-node control plane でも `etcd` bootstrap は 1 回だけ実行します。

```bash
talosctl bootstrap \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

bootstrap 後、同じノード上で `etcd` と Kubernetes control plane の static pod が立ち上がります。

## 5. etcd と control plane の状態を確認する

まず `etcd` の状態を確認します。

```bash
talosctl service etcd \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
talosctl etcd members \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

control plane static pod の生成を確認します。

```bash
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

`etcd` が `Pre` のままなら、bootstrap 未実施、installer image の不整合、または古い `etcd` データの残存を疑います。

## 6. kubeconfig を取得する

Kubernetes API が起動したら `kubeconfig` を取得します。

```bash
talosctl kubeconfig "$KUBECONFIG" \
  --merge=false \
  --force \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

上書きしたくない場合は別パスへ出力して確認後に配置します。

## 7. Kubernetes 側を確認する

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide
```

最低限の確認ポイント:

- control plane ノードが `Ready` になる
- `kube-system` の control plane 関連 Pod が起動する
- CNI 導入後に `coredns` が安定する

## トラブル時の確認ポイント

`talosctl health` で control plane の全体状態を確認できます。

```bash
talosctl health \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --control-plane-nodes "$CONTROL_PLANE_IP"
```

よく見るコマンド:

```bash
talosctl logs etcd \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
talosctl dmesg \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
talosctl get staticpodstatus \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
talosctl containers -k \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
talosctl logs controller-runtime \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

## 実施順の要点

要点だけに絞ると、必要な順序は次の通りです。

1. maintenance mode に `--insecure` で接続する
2. machine config と `talosconfig` を生成する
3. control plane ノードへ machine config を適用する
4. `talosctl bootstrap` を 1 回だけ実行する
5. `etcd` と static pod を確認する
6. `kubeconfig` を取得して `kubectl` で確認する

## やってはいけないこと

- TalOS API endpoint に VIP を使う
- bootstrap を複数回実行する
- `image.yml` と違う installer image でインストールする
- 実運用の `talosconfig` や `kubeconfig` を Git に置く
