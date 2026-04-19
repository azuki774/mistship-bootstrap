# TalOS クラスタのネットワーク構成方針

この文書は、`mistship-bootstrap` で bootstrap 対象にしている Kubernetes ネットワーク構成を記録するための設計メモです。

対象は TalOS v1.12 系を前提にした single-cluster 構成です。

## 現在の判断

このクラスタでは、次の構成を採用します。

- `TalOS`
- `KubeSpan`
- `Calico`
- `Calico eBPF dataplane`
- `kube-proxy` なし

状態:

- 方針として採用済み
- この文書は設計判断の記録であり、設定反映は別作業とする

言い換えると、ノード間の暗号化と到達性は `KubeSpan` に任せ、Pod ネットワーク、`NetworkPolicy`、Service 転送は `Calico eBPF` に寄せます。

## 採用理由

### `KubeSpan` を使う理由

- TalOS に組み込まれた WireGuard ベースの node-to-node メッシュであり、TalOS と自然に統合できる
- 離れたネットワーク間のノード接続を TalOS 側で一貫して扱える
- ノード間暗号化を CNI 実装から分離できる

### `Calico` を使う理由

- `NetworkPolicy` が必要である
- TalOS には `Calico` の公式導入ガイドがある
- `KubeSpan` と責務を分離しやすい

### `Calico eBPF` を選ぶ理由

- `NetworkPolicy` だけでなく、Pod networking と Service handling も一体で扱える
- `kube-proxy` を外し、Service dataplane の責務を `Calico` に集約できる
- 今回は保守性よりも、機能性と将来の拡張余地を優先する

## 実装上の前提

- `KubeSpan` は node-to-node 通信用の WireGuard として使う
- `KubeSpan` は通常の node-to-node 経路の唯一の overlay とし、`tailscale0` は管理アクセス専用に寄せる
- Pod ネットワークと `NetworkPolicy` は `Calico` に任せる
- Service 転送は `Calico eBPF` に任せる
- `kube-proxy` は導入しない
- TalOS のデフォルト CNI は無効化する

TalOS 側では、`cluster.network.cni.name` を `none` にする前提で構成します。

`KubeSpan` では `advertiseKubernetesNetworks` を有効化しません。
`Calico` は Pod IP を独自に扱うため、この設定を併用しない前提で設計します。

`KubeSpan` の endpoint には Tailscale の address range を載せません。
TalOS の `filters.endpoints` で `100.64.0.0/10` と `fd7a:115c:a1e0::/48` を除外し、通常の node 間通信を `tailscale0` に乗せない前提で運用します。

`allowDownPeerBypass` は無効のまま運用します。
`KubeSpan` が不通でも平文経路へ自動で逃がさないことで、node 間暗号化の前提を崩さないようにします。

## 運用メモ

- `KubeSpan` 用に UDP `51820` を通す
- `Tailscale` は TalOS API や緊急時の管理アクセスにだけ使い、通常の node-to-node 通信には使わない
- TalOS ingress firewall patch 自体はこの repo では管理せず、private repo 側で別管理する
- `Calico eBPF` は `kube-proxy` なし前提なので、bootstrap 手順と manifest 適用順を固定する

## リスク

- `Calico eBPF` は `NFTables` よりも構成が攻めている
- 問題が起きたとき、切り分けは `NFTables` より難しくなる
- `KubeSpan` と `Calico` の責務分担を崩す設定を入れると、経路問題の調査が難しくなる

## 現在の懸念

現時点で、`KubeSpan` と `Calico` の組み合わせで経路または MTU 問題が再現していると見ています。
そのため、通常の node-to-node 通信は `KubeSpan` に寄せたまま、`tailscale0` を通常経路の候補から外して切り分ける前提で進めます。

この切り分けでも問題が残る場合は、underlay MTU の再確認と `kubespan.mtu` の調整を次の候補にします。

## 参考

- TalOS `KubeSpan`
- TalOS `Deploy Calico CNI`
- Calico `Install in eBPF mode`
