# mistship-bootstrap

`mistship-bootstrap` は、TalOS クラスタを手元で bootstrap し、Argo CD を入れて GitOps に渡すまでを管理する public repo です。

この repo に置くのは、公開可能な定義、SOPS で暗号化した cluster input、ローカル bootstrap 手順です。継続運用用の manifest や CI/CD からの cluster apply は扱いません。

`mistship-bootstrap` という名前どおり、この repo の責務は bootstrap までです。Argo CD 導入後の継続運用は別の deploy repo に渡します。

## 何を置くか

- TalOS イメージ定義
- 公開可能な patch
- bootstrap 用 manifest
- SOPS で暗号化した cluster input
- bootstrap 手順書
- ローカル bootstrap 用 script

## 何を置かないか

- 平文の `cluster-inputs.env`、`cluster-secrets.yaml`
- `talosconfig`、`kubeconfig`
- 生成済み machine config
- Argo CD 導入後の継続運用 manifest
- 実環境固有の TalOS ingress firewall patch
- deploy repo を指す `Application`

## 最短フロー

初回だけ `direnv allow` を実行すると、この repo に入ったとき自動で `.#default` の dev shell が読み込まれます。`direnv` を使わない場合は、これまでどおり `nix develop` を実行します。

```bash
direnv allow
bash ./scripts/ops/decrypt-cluster-secrets.sh
bash ./scripts/ops/prepare-cluster-access.sh
```

これは、すでに SOPS 暗号化済み input がある場合の手順です。暗号化済み input が default path の `secrets/mistship/` 以外にある場合は、`MISTSHIP_CLUSTER_INPUTS_SOPS_FILE` と `MISTSHIP_CLUSTER_SECRETS_SOPS_FILE` を指定して復号します。

初回 bootstrap でまだ input がない場合は、先に次を行います。

```bash
direnv allow
mkdir -p .secret/generated .secret/nodes
cp ./templates/cluster-inputs.env.example .secret/cluster-inputs.env
$EDITOR .secret/cluster-inputs.env
talosctl gen secrets -o .secret/cluster-secrets.yaml
chmod 600 .secret/cluster-inputs.env .secret/cluster-secrets.yaml
bash ./scripts/ops/prepare-cluster-access.sh
```

その後は次の順で進めます。

1. [docs/bootstrap.md](docs/bootstrap.md) で TalOS control plane を bootstrap
2. `GENERATE_KUBECONFIG=true bash ./scripts/ops/prepare-cluster-access.sh` で `kubeconfig` を取得
3. [docs/gitops-bootstrap.md](docs/gitops-bootstrap.md) で Calico と Argo CD を導入

`prepare-cluster-access.sh` は再実行できます。既存の `talosconfig` は既定で温存され、`REGENERATE_TALOSCONFIG=true` を付けたときだけ再生成します。

## 秘密情報

この repo に commit してよいのは、公開可能な定義と SOPS で暗号化した input だけです。平文 secret は `.secret/` にだけ置きます。

詳細:

- [docs/secrets.md](docs/secrets.md)
- [docs/agents/commit-secret-reviewer.md](docs/agents/commit-secret-reviewer.md)

## CI

GitHub Actions は検証専用で、cluster への deploy や apply はしません。実 secret の復号もしません。

- `nix-ci`: ツールの起動確認、shell script の構文確認、docs link の確認
- `talos-preflight`: manifest 検証、patch 検証、dummy input による TalOS 生成経路の確認

## Docs

- [docs/bootstrap.md](docs/bootstrap.md)
- [docs/gitops-bootstrap.md](docs/gitops-bootstrap.md)
- [docs/secrets.md](docs/secrets.md)
- [docs/networking-stack.md](docs/networking-stack.md)
- [docs/networking-migration.md](docs/networking-migration.md)
- [docs/tailscale.md](docs/tailscale.md)
- [docs/agents/conventional-commit-writer.md](docs/agents/conventional-commit-writer.md)
- [manifests/bootstrap/README.md](manifests/bootstrap/README.md)
