# TalOS Tailscale Extension

`image.yml` には `siderolabs/tailscale` extension を含めていますが、それだけでは node は tailnet に参加しません。
この repo では、`controlplane` と `worker` の machine config に対して role ごとに Tailscale 設定を埋め込む最小構成を扱います。

## 前提

- TalOS image に `siderolabs/tailscale` が入っている
- 既存の tailnet がある
- Tailscale admin で `tag:mistship-controlplane` と必要なら `tag:mistship-worker` を使える
- role ごとに auth key を発行できる

`tagOwners` の最小例:

```json
{
  "tagOwners": {
    "tag:mistship-controlplane": ["autogroup:admin"],
    "tag:mistship-worker": ["autogroup:admin"]
  }
}
```

## 1. auth key を作る

Tailscale admin で role ごとの auth key を作ります。

control plane 用の例:

- tag: `tag:mistship-controlplane`
- `Pre-approved`: on
- 単一 node なら `one-off`

worker 用の例:

- tag: `tag:mistship-worker`
- `Pre-approved`: on
- role 共通 config を複数台へ使い回すなら hostname は auth key 側で固定しない

## 2. cluster input に Tailscale 値を入れる

平文の `cluster-inputs.env` か、その元になる暗号化済み input に次を入れます。

```bash
TAILSCALE_CONTROLPLANE_ENABLED=true
TAILSCALE_CONTROLPLANE_AUTHKEY=tskey-controlplane-xxxxxxxx
TAILSCALE_CONTROLPLANE_HOSTNAME="${CLUSTER_NAME}-controlplane"
TAILSCALE_CONTROLPLANE_TAGS=tag:mistship-controlplane
TAILSCALE_CONTROLPLANE_AUTH_ONCE=true
TAILSCALE_CONTROLPLANE_ACCEPT_DNS=false

TAILSCALE_WORKER_ENABLED=true
TAILSCALE_WORKER_AUTHKEY=tskey-worker-xxxxxxxx
TAILSCALE_WORKER_HOSTNAME=
TAILSCALE_WORKER_TAGS=tag:mistship-worker
TAILSCALE_WORKER_AUTH_ONCE=true
TAILSCALE_WORKER_ACCEPT_DNS=false
```

`TAILSCALE_CONTROLPLANE_EXTRA_ARGS` と `TAILSCALE_WORKER_EXTRA_ARGS` を使うと、`tailscale up` に追加引数を渡せます。
`TS_ROUTES` のような subnet router 用の設定は、この最小構成では使いません。

`TAILSCALE_WORKER_HOSTNAME` は既定で空です。`worker.yaml` は role 共通 config なので、固定 hostname を既定にすると複数 worker へ同じ config を適用したときに衝突しやすくなります。個別 hostname を付けたい場合だけ明示します。

## 3. TalOS config を生成する

```bash
bash ./scripts/ops/prepare-cluster-access.sh
```

`TAILSCALE_CONTROLPLANE_ENABLED=true` のときは `controlplane.yaml` に、`TAILSCALE_WORKER_ENABLED=true` のときは `worker.yaml` に、それぞれ `tailscale` の `ExtensionServiceConfig` を埋め込みます。

## 4. node に適用する

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
talosctl apply-config --insecure --nodes "$WORKER_IP" --file "$WORKER_CONFIG"
```

node が起動すると、tailscale extension が `TS_AUTHKEY` を使って tailnet へ参加します。worker は cluster bootstrap 後に追加します。

## 5. 確認

TalOS 側:

```bash
talosctl get extensionserviceconfigs \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"

talosctl get addresses \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

見たいもの:

- `ExtensionServiceConfig` に `tailscale` がある
- `tailscale0` interface がある

Tailscale admin 側:

- `${CLUSTER_NAME}-controlplane` が見える
- tag が `tag:mistship-controlplane`
- worker も有効なら、worker node が見える
- worker に hostname を明示した場合はその名前、明示しない場合は TalOS 側の node 名で見える
- tailnet 参加済み端末から node の Tailscale IP へ到達できる

## 補足

- `KubeSpan` は node 間メッシュのまま維持します。Tailscale は管理アクセスの追加経路です。
- `TS_ACCEPT_DNS=false` を既定にしています。TalOS 側で `hostDNS` を使っているため、最初から tailnet DNS を被せません。
- `TAILSCALE_*_TAGS` は `tailscale up --advertise-tags=...` へ変換されます。
