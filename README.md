# mistship

`mistship` は、TalOS ベースの Kubernetes クラスタを手元で bootstrap し、Argo CD を導入して GitOps に引き渡すまでを管理する public repository です。

このリポジトリが扱うのは、公開可能な定義、ローカル bootstrap 用の手順、SOPS で暗号化した cluster input です。継続運用用の deploy repo、平文 secret、CI/CD からのクラスタ操作は扱いません。

## この repo の責務

- TalOS Image Factory 向けの公開可能なイメージ定義
- TalOS machine config に適用する公開可能な patch
- SOPS で暗号化した cluster input
- Calico と Argo CD を入れるまでの bootstrap manifest
- ローカル bootstrap 手順と検証用スクリプト

## この repo で扱わないもの

- CI/CD からの `kubectl` / `talosctl` apply
- 平文の `cluster-inputs.env`、`cluster-secrets.yaml`
- `talosconfig`、`kubeconfig`、生成済み machine config
- Argo CD 導入後の継続運用 manifest
- deploy repo を指す初回 `Application` / `AppProject`

## Bootstrap Flow

1. `nix develop` でローカルの作業シェルに入る
2. `bash ./scripts/decrypt-cluster-secrets.sh` で SOPS 暗号化 input を `.secret/` へ復号する
3. `bash ./scripts/prepare-cluster-access.sh` で TalOS 用の machine config と `talosconfig` を生成する
4. [docs/bootstrap.md](docs/bootstrap.md) に従って control plane を bootstrap する
5. `GENERATE_KUBECONFIG=true bash ./scripts/prepare-cluster-access.sh` で `kubeconfig` を取得する
6. `bash ./scripts/apply-bootstrap-manifests.sh` で Calico と Argo CD を導入する

ここまでがこの repo の責務です。Argo CD が起動した後の継続反映は別の deploy repo に渡します。

## Repo Map

```text
.
├── .sops.yaml
├── README.md
├── docs/
│   ├── bootstrap.md
│   ├── gitops-bootstrap.md
│   ├── networking-migration.md
│   ├── networking-stack.md
│   └── secrets.md
├── flake.nix
├── image.yml
├── manifests/
│   └── infra/
│       ├── README.md
│       ├── argocd/
│       ├── calico/
│       └── ebpf-demo/
├── patches/
│   ├── common.yaml
│   ├── controlplane.yaml
│   └── worker.yaml
├── scripts/
│   ├── apply-bootstrap-manifests.sh
│   ├── apply-calico.sh
│   ├── decrypt-cluster-secrets.sh
│   └── prepare-cluster-access.sh
├── secrets/
│   └── mistship/
└── templates/
    └── cluster-inputs.env.example
```

## Nix 開発環境

[flake.nix](flake.nix) の `devShell` で TalOS bootstrap に必要な CLI を提供します。

```bash
nix develop
```

主に入るコマンド:

- `talosctl`
- `talhelper`
- `kubectl`
- `kubeconform`
- `jq`
- `yq`
- `sops`
- `age`

シェル起動時には次を既定設定します。

- `MISTSHIP_SECRETS_DIR=${MISTSHIP_SECRETS_DIR:-<repo-root>/.secret}`
- `TALOSCONFIG=${TALOSCONFIG:-$MISTSHIP_SECRETS_DIR/talosconfig}`
- `KUBECONFIG=${KUBECONFIG:-$MISTSHIP_SECRETS_DIR/kubeconfig}`

## Secret Boundary

この public repo には平文 secret を置きません。置いてよいのは、公開可能な定義と、SOPS で暗号化した cluster input だけです。

commit してよいもの:

- `image.yml`、`patches/*.yaml`
- `manifests/infra/` 配下の公開可能な bootstrap manifest
- `secrets/mistship/*.sops.env`
- `secrets/mistship/*.sops.yaml`
- 手順書、テンプレート、検証スクリプト

commit しないもの:

- `.secret/` 配下の復号結果
- `talosconfig`、`kubeconfig`
- 生成済み `controlplane.yaml`、`worker.yaml`
- 秘密鍵、証明書、token、実 IP や実 FQDN を含むファイル

詳細は [docs/secrets.md](docs/secrets.md) と [docs/commit-secret-reviewer.md](docs/commit-secret-reviewer.md) を参照してください。

## CI の役割

この repo の GitHub Actions は検証専用です。live cluster への apply や実 secret の復号は行いません。

- `nix-ci`: ツールチェイン、shell script 構文、docs リンク整合を確認する
- `talos-preflight`: manifest、TalOS patch、dummy input による config 生成経路を確認する

## Docs

- [docs/bootstrap.md](docs/bootstrap.md): TalOS control plane を立ち上げるまでの手順
- [docs/gitops-bootstrap.md](docs/gitops-bootstrap.md): Calico と Argo CD を入れて GitOps へ渡す手順
- [docs/secrets.md](docs/secrets.md): SOPS で暗号化した cluster input の扱い
- [docs/networking-stack.md](docs/networking-stack.md): 採用するネットワーク構成の判断
- [docs/networking-migration.md](docs/networking-migration.md): 既存 single-node クラスタを再 bootstrap で切り替える手順
- [manifests/infra/README.md](manifests/infra/README.md): bootstrap manifest の責務と適用順

TalOS の system extension を使う場合は、起動用イメージだけでなく installer image も同じ schematic に合わせます。詳細は [image.yml](image.yml) と [docs/bootstrap.md](docs/bootstrap.md) を参照してください。
