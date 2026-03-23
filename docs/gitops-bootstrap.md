# GitOps Bootstrap

TalOS bootstrap 後に、Calico と Argo CD を入れるための最短手順です。

## 前提

- [docs/bootstrap.md](bootstrap.md) が完了している
- `KUBECONFIG` が使える

## 適用

```bash
bash ./scripts/apply-bootstrap-manifests.sh
```

このスクリプトは次を行います。

1. `scripts/apply-calico.sh` で Calico を staged apply
2. `manifests/bootstrap/argocd/` を `kubectl apply --server-side --force-conflicts -k` で適用

Argo CD の upstream manifest にはサイズの大きい CRD が含まれるため、client-side apply だと
`metadata.annotations: Too long` で失敗し得ます。この repo では bootstrap 時に server-side apply を使います。
過去に client-side apply で途中まで作られた resource があっても、bootstrap 側が field ownership を引き取れるように `--force-conflicts` も付けます。

## 確認

```bash
kubectl --kubeconfig "$KUBECONFIG" -n calico-system get pods
kubectl --kubeconfig "$KUBECONFIG" -n argocd get pods
```

見たいもの:

- Calico が `Ready`
- Argo CD が `Ready`
- `kube-proxy` がいない

Argo CD の初期 admin password を見る場合:

```bash
kubectl --kubeconfig "$KUBECONFIG" -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
```

この repo の責務はここまでです。Argo CD 導入後の継続反映は別の deploy repo に渡します。
