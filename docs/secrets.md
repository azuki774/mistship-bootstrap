# Secret Management with SOPS

`mistship-bootstrap` に置く secret 関連ファイルは、SOPS で暗号化した input だけです。平文 secret は `.secret/` にだけ置きます。

repo 名は `mistship-bootstrap` ですが、現時点の暗号化済み input の格納 path は `secrets/mistship/` のままです。

## Git に置くもの

- `secrets/mistship/cluster-inputs.sops.env`
- `secrets/mistship/cluster-secrets.sops.yaml`
- `secrets/mistship/argocd-repository.sops.yaml` を置いてもよい

`cluster-inputs.sops.env` には、必要なら Tailscale の auth key のような bootstrap 時の secret input も含められます。
その場合も平文は `.secret/cluster-inputs.env` にだけ復号します。

## Git に置かないもの

- `.secret/`
- `talosconfig`
- `kubeconfig`
- 生成済み `controlplane.yaml`、`worker.yaml`
- 生成済み `bootstrap-root-application.yaml`、`argocd-repository-secret.yaml`
- `age` private key

## 使い方

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
bash ./scripts/ops/decrypt-cluster-secrets.sh
set -a
source .secret/cluster-inputs.env
set +a
bash ./scripts/ops/prepare-cluster-access.sh
```

Argo CD で private deploy repo を読む場合は、追加で次も使えます。

```bash
cp templates/argocd-repository.yaml.example argocd-repository.yaml
sops --encrypt --input-type yaml --output-type yaml \
  --output secrets/mistship/argocd-repository.sops.yaml \
  argocd-repository.yaml
rm argocd-repository.yaml
```

## CI

CI は実 secret を復号しません。dummy 値で生成経路だけ確認します。

## 鍵管理

- `.sops.yaml` には public key だけを入れる
- private key は repo に置かない
- recipient を変えるときは `sops updatekeys` を使う

## 初回投入

1. `.sops.yaml` に public key を入れる
2. [templates/cluster-inputs.env.example](../templates/cluster-inputs.env.example) から平文 input を作る
3. `talosctl gen secrets -o cluster-secrets.yaml`
4. 必要なら [templates/argocd-repository.yaml.example](../templates/argocd-repository.yaml.example) から Argo CD 用の平文 key file を作る
5. `sops --encrypt` で `secrets/mistship/*.sops.*` を作る
6. 平文ファイルを削除する
