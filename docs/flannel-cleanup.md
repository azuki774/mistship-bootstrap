# Flannel cleanup 手順

この文書は 2 つの目的を持ちます。

- すでに cluster に残っている `Flannel` の残骸を安全側で整理する
- 新規 bootstrap 時に `Flannel` を使わない前提を明文化する

前提:

- このリポジトリの目標構成は `TalOS + Calico eBPF + kube-proxy disabled`
- `Flannel` は移行前の旧構成であり、維持対象ではない

## 1. 今ある cluster の暫定 cleanup

まず、Calico が先に収束していることを確認します。

```bash
kubectl --kubeconfig "$KUBECONFIG" -n calico-system get pods -o wide
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide | rg 'flannel|calico|kube-proxy'
```

最低限の確認ポイント:

- `calico-node` が `Ready`
- `calico-kube-controllers` が `Ready`
- node が `Ready`
- `kube-proxy` が意図せず再作成されていない

次に、cluster に残っている `Flannel` 関連 resource を棚卸しします。

```bash
nix develop .#default --command ./scripts/cleanup-flannel.sh
```

このスクリプトは、名前または namespace に `flannel` を含む以下の resource を表示します。

- `DaemonSet`
- `Pod`
- `ConfigMap`
- `ServiceAccount`
- `Role`
- `RoleBinding`
- `ClusterRole`
- `ClusterRoleBinding`
- `Namespace`

削除する場合は、棚卸し結果を確認した上で次を実行します。

```bash
nix develop .#default --command ./scripts/cleanup-flannel.sh --delete
```

確認を省略して実行したい場合だけ `--yes` を付けます。

```bash
nix develop .#default --command ./scripts/cleanup-flannel.sh --delete --yes
```

cleanup 後は再度 inventory を実行し、何も出ないことを確認します。

```bash
nix develop .#default --command ./scripts/cleanup-flannel.sh
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide | rg 'flannel|calico|kube-proxy'
kubectl --kubeconfig "$KUBECONFIG" get ds -A
```

期待状態:

- `kube-system` に `kube-flannel` Pod が残っていない
- `flannel` を含む DaemonSet / ConfigMap / RBAC が残っていない
- `calico-system` の component が引き続き `Ready`

## 2. TalOS node 側の CNI 点検

cluster resource を消しただけでは、node 側の CNI 設定ファイルが残っていない保証にはなりません。
TalOS では host filesystem を場当たり的に直接変更するより、まず現在の状態を観測します。

確認例:

```bash
talosctl ls /etc/cni/net.d \
  --talosconfig "$TALOSCONFIG" \
  --nodes "$CONTROL_PLANE_IP"
```

`flannel` を含むファイルがある場合は内容も確認します。

```bash
talosctl read /etc/cni/net.d/10-flannel.conflist \
  --talosconfig "$TALOSCONFIG" \
  --nodes "$CONTROL_PLANE_IP"
```

確認ポイント:

- active な CNI 設定が `Flannel` を向いていない
- `Calico` 導入後に `Flannel` 用の設定ファイルが残っていない

TalOS 前提では、node 側に旧 `Flannel` ファイルが残っている場合でも、まずは次を優先します。

- `patches/common.yaml` を含む正しい machine config を再適用する
- node を再起動して state が再収束するか確認する
- それでも残る場合は、in-place で host filesystem を手修正するより再 install / 再 bootstrap を優先する

理由:

- このリポジトリの前提は immutable に近い再現手順の維持である
- node 上だけの手修正は再現性を落とし、原因切り分けを難しくする

## 3. 新規 bootstrap 時に Flannel を使わないための固定点

新規構築では `Flannel` を入れないことが重要です。
このリポジトリでは、次の 3 点でそれを固定します。

1. [`patches/common.yaml`](/home/azuki/work/mistship/patches/common.yaml) で TalOS の default CNI を無効化する
1. [`patches/common.yaml`](/home/azuki/work/mistship/patches/common.yaml) で `kube-proxy` を無効化する
1. Kubernetes API 起動後すぐに [`scripts/apply-calico.sh`](/home/azuki/work/mistship/scripts/apply-calico.sh) で Calico を staged apply する

現時点での固定値:

- `cluster.network.cni.name: none`
- `cluster.proxy.disabled: true`

この前提により、fresh bootstrap では TalOS managed `Flannel` を使わず、Pod networking と Service dataplane は Calico 側へ寄せます。

検証は [`scripts/validate-manifests.sh`](/home/azuki/work/mistship/scripts/validate-manifests.sh) でも行います。
`patches/common.yaml` から上記設定が外れると CI で検出できる状態にします。

## 4. 受け入れ条件との対応

Issue #14 の受け入れ条件に対して、このリポジトリで担保するものは次の通りです。

- `kube-system` に `kube-flannel` Pod が残っていない
  - [`scripts/cleanup-flannel.sh`](/home/azuki/work/mistship/scripts/cleanup-flannel.sh) と確認コマンドで対応
- node 上で Flannel 管理の CNI 設定が active でない
  - `talosctl ls/read` の確認手順で対応
- manual cleanup が必要なら docs / migration notes に反映されている
  - この文書と [`docs/networking-migration.md`](/home/azuki/work/mistship/docs/networking-migration.md) で対応
- cleanup 後の確認で Calico-only networking を確認できる
  - `calico-system` の確認コマンドと `kubectl get pods -A` の確認で対応
