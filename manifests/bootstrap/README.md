# Infrastructure Manifests

`manifests/bootstrap/` には、GitOps が動き出す前に local operator が適用する公開可能な Kubernetes manifest を置きます。

この repo の既定 bootstrap で使うディレクトリ:

- `calico/`
  - bootstrap 必須
  - `scripts/apply-calico.sh` で staged apply する
- `argocd/`
  - bootstrap 必須
  - Argo CD install manifest を version pin した kustomization として持つ

補助・参考用途のディレクトリ:

- `ebpf-demo/`
  - bootstrap 既定では apply しない
  - 手動検証用の manifest

含めてよいもの:

- Namespace、RBAC、Deployment、Service などの公開可能な定義
- GitOps 起動前に operator がローカルで適用してよい基盤 manifest

含めないもの:

- Secret の実体
- 実運用の `kubeconfig`
- 実 IP、実 FQDN、認証情報を含むファイル
- private deploy repo を指す具体的な `Application`

bootstrap 既定の適用順は [scripts/apply-bootstrap-manifests.sh](../../scripts/apply-bootstrap-manifests.sh) に固定します。

1. `calico/` を staged apply する
2. `argocd/` を `kubectl apply -k` で導入する

`ebpf-demo/` のような任意 manifest はこのスクリプトでは apply しません。
