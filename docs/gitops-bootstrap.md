# GitOps Bootstrap with Argo CD

この文書は、TalOS control plane の bootstrap が終わり、`kubeconfig` が取得できた後に Calico と Argo CD を導入するための手順です。

この repo の責務は Argo CD 本体の導入までです。private deploy repo を指す初回 `Application` / `AppProject` は別 Issue で扱います。

## 前提

- [docs/bootstrap.md](bootstrap.md) が完了している
- `KUBECONFIG` が `.secret/kubeconfig` を指している
- Kubernetes API に `kubectl` で接続できる

確認例:

```bash
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide
kubectl --kubeconfig "$KUBECONFIG" get pods -A
```

## 1. Bootstrap manifest を適用する

Calico と Argo CD の適用順はスクリプトに固定しています。

```bash
bash ./scripts/apply-bootstrap-manifests.sh
```

このスクリプトが行うこと:

1. [scripts/apply-calico.sh](../scripts/apply-calico.sh) で Calico を staged apply する
2. [manifests/infra/argocd/kustomization.yaml](../manifests/infra/argocd/kustomization.yaml) を `kubectl apply -k` で適用する
3. optional manifest は既定では apply しない

## 2. 収束を確認する

```bash
kubectl --kubeconfig "$KUBECONFIG" -n calico-system get pods -o wide
kubectl --kubeconfig "$KUBECONFIG" -n argocd get pods -o wide
```

確認ポイント:

- `calico-node`、`calico-kube-controllers` が `Ready`
- `argocd-server`、`argocd-application-controller`、`argocd-repo-server` が `Ready`
- `kube-proxy` が存在しない

Argo CD の初期 admin password を確認したい場合:

```bash
kubectl --kubeconfig "$KUBECONFIG" -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
echo
```

## 3. この repo の責務はここで終わる

Argo CD が起動したら、継続反映は deploy repo に渡します。

この Issue では次をまだ扱いません。

- private deploy repo を指す `Application`
- `AppProject`
- repo credential / SSH deploy key / PAT
- Argo CD self-management

Argo CD install manifest の version pin は [manifests/infra/argocd/kustomization.yaml](../manifests/infra/argocd/kustomization.yaml) で管理します。
