# Secret Management with SOPS

`mistship-bootstrap` に置く secret 関連ファイルは、SOPS で暗号化した input だけです。平文 secret は `.secret/` にだけ置きます。

暗号化済み input の default path は `secrets/mistship/` です。別 path に置く場合は、復号時に `MISTSHIP_CLUSTER_INPUTS_SOPS_FILE` と `MISTSHIP_CLUSTER_SECRETS_SOPS_FILE` で上書きします。

## Git に置くもの

- `secrets/mistship/cluster-inputs.sops.env`
- `secrets/mistship/cluster-secrets.sops.yaml`

`cluster-inputs.sops.env` には、必要なら control plane / worker 用 Tailscale auth key のような bootstrap 時の secret input も含められます。
その場合も平文は `.secret/cluster-inputs.env` にだけ復号します。

## Git に置かないもの

- `.secret/`
- `talosconfig`
- `kubeconfig`
- 生成済み `controlplane.yaml`、`worker.yaml`
- `age` private key

## 既存の暗号化済み input を使う

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
bash ./scripts/ops/decrypt-cluster-secrets.sh
bash ./scripts/ops/prepare-cluster-access.sh
```

暗号化済み input が別 path にある場合の例:

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
MISTSHIP_CLUSTER_INPUTS_SOPS_FILE=secrets/mistship.bak/cluster-inputs.sops.env \
MISTSHIP_CLUSTER_SECRETS_SOPS_FILE=secrets/mistship.bak/cluster-secrets.sops.yaml \
bash ./scripts/ops/decrypt-cluster-secrets.sh
bash ./scripts/ops/prepare-cluster-access.sh
```

`prepare-cluster-access.sh` は `source` ではなく `bash` で実行します。必要な値が未設定なら `.secret/cluster-inputs.env` を自動で読み込みます。

## CI

CI は実 secret を復号しません。dummy 値で生成経路だけ確認します。

## 鍵管理

- `.sops.yaml` には public key だけを入れる
- private key は repo に置かない
- recipient を変えるときは `sops updatekeys` を使う

## 初回投入

1. `.sops.yaml` に public key を入れる
2. `mkdir -p .secret/generated .secret/nodes`
3. [templates/cluster-inputs.env.example](../templates/cluster-inputs.env.example) から `.secret/cluster-inputs.env` を作り、cluster 固有の値へ更新する
4. `talosctl gen secrets -o .secret/cluster-secrets.yaml`
5. 必要なら `bash ./scripts/ops/prepare-cluster-access.sh` を実行して生成を確認する
6. `sops --encrypt` で `secrets/mistship/*.sops.*` を作る
7. 平文ファイルを削除する
