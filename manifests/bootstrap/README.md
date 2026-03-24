# Bootstrap Manifests

`manifests/bootstrap/` には、GitOps 起動前に local operator が適用する公開可能な manifest を置きます。

## 既定で使うもの

- `calico/`
- `argocd/`

## 条件付きで使うもの

- `gitops-entry/`

## 参考用

- `ebpf-demo/`

## 適用順

```bash
bash ./scripts/ops/apply-bootstrap-manifests.sh
```

このスクリプトは `calico/` を先に適用し、その後 `argocd/` を server-side apply で適用します。
さらに、`ARGOCD_DEPLOY_REPO_NAME` と SSH deploy key がそろっている場合だけ `gitops-entry/` に相当する render 済み manifest を適用します。
Argo CD の CRD は大きいため、client-side apply だと annotation size 制限に当たる場合があります。
また、過去の client-side apply が残している field manager conflict を bootstrap 側で解消するため、`--force-conflicts` を使います。
`ebpf-demo/` は既定では apply しません。
