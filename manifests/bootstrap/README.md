# Bootstrap Manifests

`manifests/bootstrap/` には、GitOps 起動前に local operator が適用する公開可能な manifest を置きます。

## 既定で使うもの

- `calico/`
- `argocd/`

## 参考用

- `ebpf-demo/`

## 適用順

```bash
bash ./scripts/ops/apply-bootstrap-manifests.sh
```

このスクリプトは `calico/` を先に適用し、その後 `argocd/` を server-side apply で適用します。
Argo CD の CRD は大きいため、client-side apply だと annotation size 制限に当たる場合があります。
`ebpf-demo/` は既定では apply しません。
