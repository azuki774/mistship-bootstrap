# TalOS ネットワーク移行手順

この手順は、既存の single-node クラスタを `Flannel + kube-proxy` から `TalOS + KubeSpan + Calico eBPF + kube-proxy disabled` に切り替えるための停止あり再構築手順です。

このリポジトリでは live cutover は扱いません。既存クラスタの Pod や node を維持したまま段階的に CNI を差し替えるのではなく、クラスタを止めて再 bootstrap します。

## 前提

- 既存クラスタは single-node 構成である
- 現在の `kube-system` には `kube-flannel` と `kube-proxy` がいる
- control plane の実 IP と TalOS 設定は Git の外にある
- 既存 workload をそのまま残す必要はない

## 移行方針

移行は次の順序で行います。

1. 現在のクラスタ状態を記録する
1. 既存クラスタを停止する
1. TalOS machine config を `KubeSpan` と `Calico eBPF` 前提で再生成する
1. control plane を再インストールする
1. `talosctl bootstrap` を 1 回だけ実行する
1. Calico を staged apply する
1. 残りの infra を適用する
1. worker を再追加する

## 1. 現在の状態を記録する

再構築前に、今の node と system Pod を確認しておきます。

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide
kubectl --kubeconfig "$KUBECONFIG" get ds -A
```

記録しておくべき点:

- node 名
- control plane の実 IP
- `kube-flannel` と `kube-proxy` の稼働有無
- 既存 workload が残っているか

## 2. 既存クラスタを停止する

single-node なので、ここで旧クラスタを止めて再構築します。

- 実 workload が必要なら先に退避する
- 既存の kubeconfig は移行後の確認用として残す
- 旧 `Flannel` / `kube-proxy` を前提にした手作業はしない

この段階で node 上の旧クラスタを残したまま Calico を重ねないことが重要です。`kube-proxy` と Calico eBPF を同時に中途半端に動かすと、切り分けが難しくなります。

## 3. TalOS 設定を再生成する

`docs/bootstrap.md` の fresh bootstrap 手順に従って、同じ `.env` と `cluster-secrets.yaml` から machine config を再生成します。

再生成時の要点:

- `machine.network.kubespan.enabled: true`
- `machine.network.kubespan.advertiseKubernetesNetworks: false`
- `cluster.network.cni.name: none`
- `cluster.proxy.disabled: true`

`worker.yaml` も同じ secrets から生成します。

## 4. control plane を再インストールする

control plane ノードへ `apply-config --insecure` を流し込み、TalOS を再構成します。

```bash
talosctl apply-config --insecure --nodes "$CONTROL_PLANE_IP" --file "$CONTROL_PLANE_CONFIG"
```

その後、`talosctl bootstrap` を 1 回だけ実行します。

```bash
talosctl bootstrap \
  --talosconfig "$TALOSCONFIG" \
  --endpoints "$CONTROL_PLANE_IP" \
  --nodes "$CONTROL_PLANE_IP"
```

## 5. Calico を入れる

Kubernetes API が上がったら、`kubeconfig` を取得して Calico を staged apply します。

順序は [`scripts/apply-calico.sh`](/home/azuki/work/mistship/scripts/apply-calico.sh) に固定しています。
`kubernetes-services-endpoint` は [`scripts/apply-calico.sh`](/home/azuki/work/mistship/scripts/apply-calico.sh) が `kubeconfig` から解決した API endpoint で生成します。single-node control plane では通常 `https://<CONTROL_PLANE_IP>:6443` を使います。

```bash
KUBECONFIG="$KUBECONFIG" nix develop .#default --command ./scripts/apply-calico.sh
```

## 6. 残りの infra を適用する

Calico が安定したら、`manifests/infra/` 配下の公開可能な manifest を適用します。

```bash
kubectl --kubeconfig "$KUBECONFIG" apply --recursive -f manifests/infra
```

## 7. worker を再追加する

worker を戻す場合は、再生成した `worker.yaml` を使って `apply-config` します。

```bash
talosctl apply-config --insecure --nodes "$WORKER_IP" --file "$WORKER_CONFIG"
```

新しい worker は Calico の DaemonSet が入るまで一時的に `NotReady` になることがありますが、Calico が展開されれば `Ready` に収束します。

## 8. 収束確認

移行完了後は次を確認します。

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A -o wide
kubectl --kubeconfig "$KUBECONFIG" -n calico-system get pods -o wide
```

確認ポイント:

- `kube-flannel` がいない
- `kube-proxy` がいない
- Calico の各 component が `Ready`
- `coredns` が Running
- node が `Ready`

## 失敗時

Calico が起動しない場合は、まず次を確認します。

- `kubeconfig` の API endpoint が実際の control plane endpoint と一致しているか
- `cluster.network.cni.name: none` が入っているか
- `cluster.proxy.disabled: true` が入っているか
- 旧 `Flannel` / `kube-proxy` の残骸が node に残っていないか

## 参考

- [`docs/bootstrap.md`](/home/azuki/work/mistship/docs/bootstrap.md)
- [`docs/networking-stack.md`](/home/azuki/work/mistship/docs/networking-stack.md)
