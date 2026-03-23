# Bootstrap Manifests

`manifests/bootstrap/` には、GitOps 起動前に local operator が適用する公開可能な manifest を置きます。

## 既定で使うもの

- `calico/`
- `argocd/`

## 参考用

- `ebpf-demo/`

## 適用順

```bash
bash ./scripts/apply-bootstrap-manifests.sh
```

このスクリプトは `calico/` を先に適用し、その後 `argocd/` を適用します。`ebpf-demo/` は既定では apply しません。
