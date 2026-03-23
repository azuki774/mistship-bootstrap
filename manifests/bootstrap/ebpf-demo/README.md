# Calico eBPF Service デモ

この手順は、`mistship-bootstrap` が bootstrap 対象にしているクラスタで `Calico eBPF` dataplane を使って `Service` 転送が動いていることを確認するためのものです。

目的:

- `nginx` Service が `kube-proxy` なしで到達できることを確認する
- Calico の eBPF NAT map に Service と backend Pod の対応が載っていることを確認する
- Calico の eBPF conntrack map に直前の通信が載っていることを確認する

このデモで使う manifest は [00-ebpf-demo.yaml](00-ebpf-demo.yaml) です。
このディレクトリは手動検証用であり、bootstrap 既定では apply しません。

## 1. デモ workload を確認する

まず、`ebpf-demo` namespace の workload が起動していることを確認します。

```bash
kubectl get all -n ebpf-demo -o wide
```

期待する状態:

- `Deployment/nginx` の `READY` が `2/2`
- `Pod/client` が `Running`
- `Service/nginx` に `CLUSTER-IP` が割り当てられている

Service と backend Pod の対応も確認します。

```bash
kubectl get svc -n ebpf-demo nginx -o wide
kubectl get endpoints -n ebpf-demo nginx -o wide
```

`endpoints` には `Deployment/nginx` の Pod IP が 2 つ並ぶ想定です。

## 2. Service 経由の通信を発生させる

`client` Pod から `nginx` Service へアクセスします。

```bash
kubectl exec -n ebpf-demo client -- sh -c 'for i in 1 2 3; do wget -qO- http://nginx >/dev/null; done'
```

レスポンス本文を見たい場合は、最後の `>/dev/null` を外します。

疎通確認だけなら次でも十分です。

```bash
kubectl exec -n ebpf-demo client -- wget -qO- http://nginx >/dev/null
```

## 3. Calico の eBPF NAT map を確認する

`calico-node` Pod を 1 つ選びます。

```bash
CALICO_NODE_POD="$(kubectl get pods -n calico-system -l k8s-app=calico-node -o jsonpath='{.items[0].metadata.name}')"
echo "$CALICO_NODE_POD"
```

続いて eBPF NAT map を表示します。

```bash
kubectl exec -n calico-system "$CALICO_NODE_POD" -- calico-node -bpf nat dump
```

確認ポイント:

- `ebpf-demo/nginx` Service の `ClusterIP:80` に対応するエントリがある
- backend として `nginx` Pod IP が 2 つ見える

`kubectl get svc` と `kubectl get endpoints` の結果を横に置くと見比べやすいです。

## 4. Calico の eBPF conntrack map を確認する

直前に作った通信が conntrack map に載っているか確認します。

```bash
kubectl exec -n calico-system "$CALICO_NODE_POD" -- calico-node -bpf conntrack dump
```

必要なら、別 terminal で通信を繰り返しながら観測します。

```bash
kubectl exec -n ebpf-demo client -- sh -c 'while true; do wget -qO- http://nginx >/dev/null; sleep 1; done'
```

見たいポイント:

- `client` Pod IP から `Service ClusterIP:80` への接続に対応する recent entry がある
- backend 側の変換後接続情報が見える

出力は環境差があるので、まず `client` Pod IP、`nginx` Service の `ClusterIP`、backend Pod IP を先に控えてから読むと追いやすいです。

## 5. 何が確認できたか

このデモで確認しているのは、単なる Pod 間疎通ではなく `Service` dataplane です。

確認できる事実:

- `cluster.proxy.disabled: true` の構成で `Service` が到達できる
- `Installation.spec.calicoNetwork.linuxDataplane: BPF` の構成で Calico が Service 転送を担当している
- Calico の eBPF NAT / conntrack map に Service 通信の状態が載る

つまり、このクラスタでは `kube-proxy` の代わりに Calico eBPF が Service dataplane を処理していることを観測できます。
