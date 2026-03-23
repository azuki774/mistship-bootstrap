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
- Pod ネットワークと `NetworkPolicy` は `Calico` に任せる
- Service 転送は `Calico eBPF` に任せる
- `kube-proxy` は導入しない
- TalOS のデフォルト CNI は無効化する

TalOS 側では、`cluster.network.cni.name` を `none` にする前提で構成します。

`KubeSpan` では `advertiseKubernetesNetworks` を有効化しません。
`Calico` は Pod IP を独自に扱うため、この設定を併用しない前提で設計します。

## 採用しなかった案

### `KubeSpan + TalOS-managed Flannel`

採用しません。

理由:

- `Flannel` 単体では `NetworkPolicy` を実装しない
- 今回の要件では不足する

### `KubeSpan + Canal`

採用しません。

理由:

- `Canal` は堅実だが、今回は `Calico eBPF` の機能を優先する
- `Flannel` dataplane を残す必然がなくなった

### `KubeSpan + Calico NFTables`

今回は第一候補にしません。

理由:

- より保守的で切り分けしやすいが、今回は `eBPF` 構成を優先する

補足:

- `Calico NFTables` は、`eBPF` 構成が期待どおりに安定しない場合の第一ロールバック先とする

### `Kilo + WireGuard`

採用しません。

理由:

- TalOS では `KubeSpan` が同系統の用途をより直接的に満たす
- このクラスタでまず必要なのは multi-cluster 機能ではない

## 運用メモ

- `KubeSpan` 用に UDP `51820` を通す
- TalOS ingress firewall patch 自体はこの repo では管理せず、private repo 側で別管理する
- `Calico eBPF` は `kube-proxy` なし前提なので、bootstrap 手順と manifest 適用順を固定する

## リスク

- `Calico eBPF` は `NFTables` よりも構成が攻めている
- 問題が起きたとき、切り分けは `NFTables` より難しくなる
- `KubeSpan` と `Calico` の責務分担を崩す設定を入れると、経路問題の調査が難しくなる

## 見直し条件

次のいずれかが発生した場合は、この判断を見直します。

- `Calico eBPF` で安定運用できない
- `kube-proxy` なし構成の運用負荷が高い
- `KubeSpan` と `Calico` の組み合わせで経路または MTU 問題が継続する
- `Calico NFTables` へ下げる方が合理的だと判断した
- TalOS 側の標準的な推奨構成が大きく変わった

## 参考

- TalOS `KubeSpan`
- TalOS `Deploy Calico CNI`
- Calico `Install in eBPF mode`
