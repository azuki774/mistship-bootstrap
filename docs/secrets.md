# Secret Management with SOPS

`mistship` は public bootstrap repo なので、平文の cluster input や TalOS / Kubernetes secret bundle は Git に含めません。

この repo に置くのは SOPS で暗号化した input だけです。local operator は bootstrap 時だけ `.secret/` に復号して使い、CI は dummy 値で生成経路だけを検証します。

## 管理対象

暗号化して Git に置くもの:

- `secrets/mistship/cluster-inputs.sops.env`
- `secrets/mistship/cluster-secrets.sops.yaml`

Git に置かないもの:

- `.secret/` 配下の復号結果
- `talosconfig`
- `kubeconfig`
- 生成済みの `controlplane.yaml`
- 生成済みの `worker.yaml`
- `age` private key

## 役割分担

- `cluster-inputs.sops.env`
  - cluster 名、control plane IP、install disk、TalOS version、schematic ID などの入力値
- `cluster-secrets.sops.yaml`
  - `talosctl gen secrets` の出力
- `.secret/cluster-inputs.env`
  - local bootstrap 時だけ作る平文の入力値
- `.secret/cluster-secrets.yaml`
  - local bootstrap 時だけ作る平文の secret bundle

## ローカル bootstrap での使い方

1. `SOPS_AGE_KEY` に operator 用の private key を入れる
2. `nix develop` で dev shell に入る
3. 復号する

```bash
export SOPS_AGE_KEY='AGE-SECRET-KEY-1...'
bash ./scripts/decrypt-cluster-secrets.sh
```

4. 変数を読み込む

```bash
set -a
source .secret/cluster-inputs.env
set +a
```

5. TalOS 生成物を作る

```bash
bash ./scripts/prepare-cluster-access.sh
```

## CI での扱い

この repo の CI は実 secret を復号しません。

- `nix-ci`
  - shell script と docs の整合を確認する
- `talos-preflight`
  - dummy 値と `talosctl gen secrets` で `prepare-cluster-access.sh` の生成経路を確認する

つまり、GitHub Actions に live cluster 用の `SOPS_AGE_KEY` を渡す設計ではありません。

## 鍵管理

- operator は各自の `age` key pair を持つ
- `.sops.yaml` には public key だけを入れる
- private key は repo に置かない

recipient を追加・削除するときは `.sops.yaml` を更新し、`sops updatekeys` を使います。

## 初回セットアップ

1. `.sops.yaml` に operator の public key を記入する
2. [templates/cluster-inputs.env.example](../templates/cluster-inputs.env.example) を元に平文の `cluster-inputs.env` を作る
3. `talosctl gen secrets -o cluster-secrets.yaml` で平文 secret bundle を作る
4. `sops --encrypt` で `secrets/mistship/cluster-inputs.sops.env` と `secrets/mistship/cluster-secrets.sops.yaml` を作る
5. 平文ファイルは削除し、作業後の `.secret/` も消す
