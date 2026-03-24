# TalOS ネットワーク移行手順

既存の single-node クラスタを `Flannel + kube-proxy` から `KubeSpan + Calico eBPF` 前提の TalOS クラスタへ切り替えるための停止あり再構築手順です。

この repo では live cutover は扱いません。旧クラスタを止めて再 bootstrap します。

## 流れ

1. 現在の cluster 状態を記録する
2. 既存 cluster を停止する
3. [docs/bootstrap.md](bootstrap.md) に従って TalOS 設定を再生成する
4. control plane に `apply-config --insecure` を流す
5. `talosctl bootstrap` を 1 回だけ実行する
6. `bash ./scripts/ops/apply-bootstrap-manifests.sh` で Calico と Argo CD を入れる
7. 必要なら worker を再追加する

## 記録しておくもの

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide
kubectl --kubeconfig "$KUBECONFIG" get ds -A
```

見るポイント:

- control plane IP
- `kube-flannel` と `kube-proxy` の有無
- 残したい workload の有無

## 再構築

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"

talosctl bootstrap \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

その後:

```bash
GENERATE_KUBECONFIG=true bash ./scripts/ops/prepare-cluster-access.sh
bash ./scripts/ops/apply-bootstrap-manifests.sh
```

## 収束確認

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide
kubectl --kubeconfig "$KUBECONFIG" -n calico-system get pods -o wide
```

見たいもの:

- `kube-flannel` がいない
- `kube-proxy` がいない
- Calico が `Ready`
- node が `Ready`

詳細な背景は [docs/networking-stack.md](networking-stack.md) を参照してください。
