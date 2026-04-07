# TalOS Bootstrap

`mistship-bootstrap` で TalOS の control plane を立ち上げるまでの手順です。node が maintenance mode で起動している前提で、次のどちらかの状態から始めます。

- 既存の SOPS 暗号化済み input があり、`.secret/` に復号して使う
- まだ input がなく、初回 bootstrap 用に `.secret/` へ平文 input を作る

## 0. 初回だけ cluster input を作る

既存の暗号化済み input があるなら、この手順は不要です。

初回だけ `direnv allow` を実行すると、この repo に入ったとき自動で `.#default` の dev shell が読み込まれます。`direnv` を使わない場合は、先に `nix develop` を実行してから同じ command を流します。

```bash
direnv allow
mkdir -p .secret/generated .secret/nodes
cp ./templates/cluster-inputs.env.example .secret/cluster-inputs.env
$EDITOR .secret/cluster-inputs.env
talosctl gen secrets -o .secret/cluster-secrets.yaml
chmod 600 .secret/cluster-inputs.env .secret/cluster-secrets.yaml
```

`.secret/cluster-inputs.env` には少なくとも次を実環境の値へ置き換えます。

- `CLUSTER_NAME`
- `CONTROL_PLANE_IP`
- `CONTROL_PLANE_ENDPOINT`
- `INSTALL_DISK`
- `INSTALL_IMAGE`

`CONTROL_PLANE_IP` は maintenance mode の `apply-config --insecure` 用です。
`CONTROL_PLANE_ENDPOINT` は bootstrap 後に使う Talos API / Kubernetes API の正規 endpoint で、現状は `mistship-cp.azuki.blue` を使います。

この平文 input を Git に置きたくない場合は、後で [docs/secrets.md](secrets.md) の手順で SOPS 暗号化済み input に変換します。

## 1. 既存の暗号化済み input がある場合は復号する

```bash
direnv allow
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
bash ./scripts/ops/decrypt-cluster-secrets.sh
```

暗号化済み input が default path の `secrets/mistship/` 以外にある場合は、復号元 path を明示します。

```bash
MISTSHIP_CLUSTER_INPUTS_SOPS_FILE=secrets/mistship.bak/cluster-inputs.sops.env \
MISTSHIP_CLUSTER_SECRETS_SOPS_FILE=secrets/mistship.bak/cluster-secrets.sops.yaml \
bash ./scripts/ops/decrypt-cluster-secrets.sh
```

## 2. TalOS 用ファイルを作る

```bash
bash ./scripts/ops/prepare-cluster-access.sh
```

`prepare-cluster-access.sh` は `source` せず、そのまま実行します。必要な値が未設定なら `.secret/cluster-inputs.env` を自動で読み込みます。環境変数を明示的に上書きしたい場合だけ、実行前に export します。

これで主に次が生成されます。

- `.secret/talosconfig`
- `.secret/nodes/controlplane.yaml`
- `.secret/nodes/worker.yaml`

control plane や worker を Tailscale に参加させる場合は、`cluster-inputs.env` に role ごとの `TAILSCALE_CONTROLPLANE_*` / `TAILSCALE_WORKER_*` を入れたうえで同じ script を使います。
詳細は [docs/tailscale.md](tailscale.md) を参照してください。

## 3. control plane に適用する

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
```

maintenance mode API では `talosctl version` の Server 側は未実装なので、ここでは事前確認に使いません。到達性を別途見たい場合は、OS レベルで疎通確認するか、そのまま `apply-config` を実行します。

maintenance mode を抜けたら通常接続で確認します。

```bash
talosctl version \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_ENDPOINT" \
  --nodes "$CONTROL_PLANE_ENDPOINT"
```

## 4. bootstrap する

```bash
talosctl bootstrap \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_ENDPOINT" \
  --nodes "$CONTROL_PLANE_ENDPOINT"
```

確認例:

```bash
talosctl service etcd \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_ENDPOINT" \
  --nodes "$CONTROL_PLANE_ENDPOINT"

talosctl get staticpods \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_ENDPOINT" \
  --nodes "$CONTROL_PLANE_ENDPOINT"
```

## 5. worker を追加する

ワーカー node を maintenance mode で起動したら、生成済みの `worker.yaml` をそのまま適用します。

`cluster-inputs.env` の `WORKER_IPS` に全ワーカーの IP をスペース区切りのリストで記入しておきます。

```bash
WORKER_IPS="192.0.2.21 192.0.2.22"
```

`prepare-cluster-access.sh` を実行すると `talosconfig` が更新され、全ワーカーが endpoints と nodes に登録されます。

各ワーカーへは個別に config を apply します。

```bash
for ip in $WORKER_IPS; do
  talosctl apply-config --insecure --nodes "$ip" --file "$WORKER_CONFIG"
done
```

worker を Tailscale に参加させる場合は、事前に `TAILSCALE_WORKER_ENABLED=true` と `TAILSCALE_WORKER_AUTHKEY` などを入れて `prepare-cluster-access.sh` を再実行しておきます。
`TAILSCALE_WORKER_HOSTNAME` は空のままだと `worker.yaml` に `TS_HOSTNAME` を書かないため、同じ config を複数 worker へ再利用しやすくなります。

適用後の確認例:

```bash
talosctl version \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_ENDPOINT" \
  --nodes "$WORKER_IP"
```

## 6. kubeconfig を取る

```bash
GENERATE_KUBECONFIG=true bash ./scripts/ops/prepare-cluster-access.sh
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
```

この command は再実行できます。既存の `.secret/talosconfig` は既定で温存し、`endpoints` と `nodes` だけを更新します。`talosconfig` 自体を再生成したい場合だけ `REGENERATE_TALOSCONFIG=true` を付けます。

TalOS ingress firewall patch はこの repo では管理せず、local で復号した `.secret/talosconfig` を使って private repo 側から別途適用します。

ここまで終わったら次へ進みます。

- [docs/gitops-bootstrap.md](gitops-bootstrap.md)
- [manifests/bootstrap/README.md](../manifests/bootstrap/README.md)
