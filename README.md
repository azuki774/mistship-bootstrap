# mistship

`mistship` は、TalOS クラスタを手元で bootstrap し、Argo CD を入れて GitOps に渡すまでを管理する public repo です。

この repo に置くのは、公開可能な定義、SOPS で暗号化した cluster input、ローカル bootstrap 手順です。継続運用用の manifest や CI/CD からの cluster apply は扱いません。

## 何を置くか

- `image.yml`
- `patches/`
- `manifests/bootstrap/`
- `secrets/mistship/*.sops.*`
- `docs/`
- bootstrap 用 script

## 何を置かないか

- 平文の `cluster-inputs.env`、`cluster-secrets.yaml`
- `talosconfig`、`kubeconfig`
- 生成済み machine config
- Argo CD 導入後の継続運用 manifest
- deploy repo を指す `Application`

## 最短フロー

```bash
nix develop
bash ./scripts/decrypt-cluster-secrets.sh
set -a; source .secret/cluster-inputs.env; set +a
bash ./scripts/prepare-cluster-access.sh
```

その後は次の順で進めます。

1. [docs/bootstrap.md](docs/bootstrap.md) で TalOS control plane を bootstrap
2. `GENERATE_KUBECONFIG=true bash ./scripts/prepare-cluster-access.sh` で `kubeconfig` を取得
3. [docs/gitops-bootstrap.md](docs/gitops-bootstrap.md) で Calico と Argo CD を導入

## ディレクトリ

```text
.
├── docs/
├── manifests/
│   └── bootstrap/
├── patches/
├── scripts/
├── secrets/
│   └── mistship/
├── templates/
├── image.yml
└── flake.nix
```

## 秘密情報

この repo に commit してよいのは、公開可能な定義と SOPS で暗号化した input だけです。平文 secret は `.secret/` にだけ置きます。

詳細:

- [docs/secrets.md](docs/secrets.md)
- [docs/commit-secret-reviewer.md](docs/commit-secret-reviewer.md)

## CI

GitHub Actions は検証専用です。

- `nix-ci`: shell script と docs link の確認
- `talos-preflight`: manifest と dummy input による TalOS 生成経路の確認

## Docs

- [docs/bootstrap.md](docs/bootstrap.md)
- [docs/gitops-bootstrap.md](docs/gitops-bootstrap.md)
- [docs/secrets.md](docs/secrets.md)
- [docs/networking-stack.md](docs/networking-stack.md)
- [docs/networking-migration.md](docs/networking-migration.md)
- [manifests/bootstrap/README.md](manifests/bootstrap/README.md)
