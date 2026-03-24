# GitOps Bootstrap

TalOS bootstrap 後に、Calico と Argo CD を入れ、その後 private deploy repo に handoff するための最短手順です。

## 前提

- [docs/bootstrap.md](bootstrap.md) が完了している
- `KUBECONFIG` が使える
- private deploy repo をまだ作っていない場合は、GitOps entry は skip してよい

## 事前設定

GitOps entry を有効にするには次の 2 つだけを用意します。

1. `.secret/cluster-inputs.env` に `ARGOCD_DEPLOY_REPO_NAME` を入れる
2. SSH deploy key を [templates/argocd-repository.yaml.example](../templates/argocd-repository.yaml.example) の形で作り、`secrets/mistship/argocd-repository.sops.yaml` として SOPS 暗号化する

hardcode している初期値は次です。private repo を作ったら適宜修正してください。

- GitHub owner: `azuki774`
- branch: `main`
- private repo 内の root path: `clusters/mistship`

## 適用

```bash
bash ./scripts/ops/apply-bootstrap-manifests.sh
```

このスクリプトは次を行います。

1. `scripts/ops/apply-calico.sh` で Calico を staged apply
2. `manifests/bootstrap/argocd/` を `kubectl apply --server-side --force-conflicts -k` で適用
3. `ARGOCD_DEPLOY_REPO_NAME` と SSH deploy key が両方そろっている場合だけ、`bootstrap-root` `Application` と Argo CD repository Secret を適用

Argo CD の upstream manifest にはサイズの大きい CRD が含まれるため、client-side apply だと
`metadata.annotations: Too long` で失敗し得ます。この repo では bootstrap 時に server-side apply を使います。
過去に client-side apply で途中まで作られた resource があっても、bootstrap 側が field ownership を引き取れるように `--force-conflicts` も付けます。

GitOps entry が有効な場合、この repo では `bootstrap-root` という `Application` を 1 つだけ作ります。
この `Application` は private deploy repo の `clusters/mistship` を監視し、その先に置かれた `AppProject` や child `Application` は private repo 側の責務で管理します。

## 確認

```bash
kubectl --kubeconfig "$KUBECONFIG" -n calico-system get pods
kubectl --kubeconfig "$KUBECONFIG" -n argocd get pods
kubectl --kubeconfig "$KUBECONFIG" -n argocd get applications
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

この repo の責務はここまでです。GitOps 入口の `bootstrap-root` 以外の継続反映は別の deploy repo に渡します。
