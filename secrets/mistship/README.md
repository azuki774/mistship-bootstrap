# Encrypted Cluster Inputs

このディレクトリには、local bootstrap 時に使う SOPS 暗号化済み cluster input を置きます。

想定ファイル:

- `cluster-inputs.sops.env`
- `cluster-secrets.sops.yaml`
- `argocd-repository.sops.yaml` (optional)

平文の `cluster-inputs.env`、`cluster-secrets.yaml`、`argocd-repository.yaml`、`talosconfig`、`kubeconfig` はここへ置きません。復号先は `.secret/` です。
