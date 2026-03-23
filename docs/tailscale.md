# TalOS Tailscale Extension

`image.yml` には `siderolabs/tailscale` extension を含めていますが、それだけでは node は tailnet に参加しません。
この repo では、control plane node を既存 tailnet に参加させる最小構成を扱います。

## 前提

- TalOS image に `siderolabs/tailscale` が入っている
- 既存の tailnet がある
- Tailscale admin で `tag:mistship-controlplane` を使える
- auth key を 1 本発行できる

`tagOwners` の最小例:

```json
{
  "tagOwners": {
    "tag:mistship-controlplane": ["autogroup:admin"]
  }
}
```

## 1. auth key を作る

Tailscale admin で control plane 用の auth key を作ります。

推奨:

- tag: `tag:mistship-controlplane`
- `Pre-approved`: on
- 単一 node なら `one-off`

## 2. cluster input に Tailscale 値を入れる

平文の `cluster-inputs.env` か、その元になる暗号化済み input に次を入れます。

```bash
TAILSCALE_CONTROLPLANE_ENABLED=true
TAILSCALE_CONTROLPLANE_AUTHKEY=tskey-xxxxxxxx
TAILSCALE_CONTROLPLANE_HOSTNAME="${CLUSTER_NAME}-controlplane"
TAILSCALE_CONTROLPLANE_TAGS=tag:mistship-controlplane
TAILSCALE_CONTROLPLANE_AUTH_ONCE=true
TAILSCALE_CONTROLPLANE_ACCEPT_DNS=false
```

`TAILSCALE_CONTROLPLANE_EXTRA_ARGS` を使うと、`tailscale up` に追加引数を渡せます。
`TS_ROUTES` のような subnet router 用の設定は、この最小構成では使いません。

## 3. TalOS config を生成する

```bash
set -a
source .secret/cluster-inputs.env
set +a

bash ./scripts/prepare-cluster-access.sh
```

`TAILSCALE_CONTROLPLANE_ENABLED=true` のとき、script は control plane 用の `ExtensionServiceConfig` を生成済み config に埋め込みます。

## 4. control plane に適用する

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
```

node が起動すると、tailscale extension が `TS_AUTHKEY` を使って tailnet へ参加します。

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
- tailnet 参加済み端末から node の Tailscale IP へ到達できる

## 補足

- `KubeSpan` は node 間メッシュのまま維持します。Tailscale は管理アクセスの追加経路です。
- `TS_ACCEPT_DNS=false` を既定にしています。TalOS 側で `hostDNS` を使っているため、最初から tailnet DNS を被せません。
- worker も参加させたい場合は、同じ env を worker 側にも展開できるよう script を拡張するか、別の patch を追加します。
