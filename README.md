# terraform-google-platform

GCP / Firebase プロジェクトの作成・設定を一元管理する Terraform Module および GitHub Actions のモノリポ。

以下の 2 つのリポジトリを統合したものです:

- [`terraform-google-firebase-project-platform`](https://github.com/MoooDoNE/terraform-google-firebase-project-platform) — Firebase / GCP サービスリソースの有効化・設定
- [`terraform-gcp-project-factory`](https://github.com/MoooDoNE/terraform-gcp-project-factory) — GCP Project 作成・SA 管理・WIF 設定

---

## Terraform Modules

### `modules/firebase-project-platform`

Firebase / GCP プロジェクトに必要なリソースを **feature variables** で選択的に作成する共通モジュール。

Terraform Registry: `cilly-yllic/firebase-project-platform/google`

```hcl
module "firebase_platform" {
  source = "cilly-yllic/firebase-project-platform/google"

  project_id = "my-project-id"
  region     = "asia-northeast1"

  firebase  = true
  firestore = true
  hosting   = true
}
```

詳細: [`modules/firebase-project-platform/`](./modules/firebase-project-platform/) / [docs](./docs/firebase-project-platform/)

### `modules/gcp-project-factory`

GCP Project 作成と Terraform 実行用 Service Account 作成・管理を行うモジュール。

```hcl
module "project_factory" {
  source = "{namespace}/gcp-project-factory/google"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"
}
```

詳細: [`modules/gcp-project-factory/`](./modules/gcp-project-factory/) / [docs](./docs/gcp-project-factory/)

---

## GitHub Actions

| Action | Path | Usage |
|--------|------|-------|
| dispatch-tfc-firebase-platform | `actions/dispatch-firebase-platform/` | `uses: MoooDoNE/terraform-google-platform/actions/dispatch-firebase-platform@main` |
| dispatch-tfc-project-factory | `actions/dispatch-project-factory/` | `uses: MoooDoNE/terraform-google-platform/actions/dispatch-project-factory@main` |

---

## Cloud Run Router

TFC notification を受けて GitHub `repository_dispatch` を発火する Cloud Run service。

詳細: [`cloud-run-router/`](./cloud-run-router/)

---

## Bootstrap (gcp-project-factory)

`infra-bootstrap` Project / Service Account / WIF を構築するための bootstrap script:

```bash
cp scripts/bootstrap.example.env .env
vi .env

make bootstrap-check   # 事前確認
make bootstrap         # リソース作成
```

詳細: [`scripts/`](./scripts/) / [docs/gcp-project-factory/bootstrap.md](./docs/gcp-project-factory/bootstrap.md)

---

## Examples

| Module | Example | Path |
|--------|---------|------|
| firebase-project-platform | minimal | [`examples/firebase-project-platform/minimal/`](./examples/firebase-project-platform/minimal/) |
| firebase-project-platform | full | [`examples/firebase-project-platform/full/`](./examples/firebase-project-platform/full/) |
| gcp-project-factory | minimal | [`examples/gcp-project-factory/minimal/`](./examples/gcp-project-factory/minimal/) |
| gcp-project-factory | complete | [`examples/gcp-project-factory/complete/`](./examples/gcp-project-factory/complete/) |

---

## ディレクトリ構成

```
terraform-google-platform/
├── modules/
│   ├── firebase-project-platform/    # Firebase / GCP サービス Module
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── modules/                  # Sub-modules (analytics, auth, firestore, …)
│   └── gcp-project-factory/          # Project 作成 Module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── data.tf
│       ├── locals.tf
│       └── modules/                  # Sub-modules (project, service-account, iam)
├── actions/
│   ├── dispatch-firebase-platform/   # GitHub Action: TFC dispatch (firebase)
│   └── dispatch-project-factory/     # GitHub Action: TFC dispatch (project-factory)
├── cloud-run-router/                 # Cloud Run: TFC notification → repository_dispatch
├── scripts/                          # Bootstrap scripts (gcp-project-factory)
├── examples/
│   ├── firebase-project-platform/
│   │   ├── minimal/
│   │   └── full/
│   └── gcp-project-factory/
│       ├── minimal/
│       └── complete/
├── docs/
│   ├── firebase-project-platform/    # Firebase Module ドキュメント
│   └── gcp-project-factory/          # Project Factory ドキュメント
├── Makefile
├── LICENSE
└── README.md
```

---

## Documentation

| Topic | Link |
|-------|------|
| Firebase Platform Architecture | [docs/firebase-project-platform/architecture.md](./docs/firebase-project-platform/architecture.md) |
| Firebase Variables Reference | [docs/firebase-project-platform/variables-reference.md](./docs/firebase-project-platform/variables-reference.md) |
| Firebase Upgrade Guide | [docs/firebase-project-platform/upgrade-guide.md](./docs/firebase-project-platform/upgrade-guide.md) |
| Project Factory Architecture | [docs/gcp-project-factory/architecture.md](./docs/gcp-project-factory/architecture.md) |
| Project Factory Bootstrap | [docs/gcp-project-factory/bootstrap.md](./docs/gcp-project-factory/bootstrap.md) |
| IAM Policy Design | [docs/gcp-project-factory/design/iam-policy.md](./docs/gcp-project-factory/design/iam-policy.md) |
| WIF Attribute Mapping | [docs/gcp-project-factory/design/wif-attribute-mapping.md](./docs/gcp-project-factory/design/wif-attribute-mapping.md) |

---

## Migration Guide

旧リポジトリからの移行:

### Terraform Module

```hcl
# Before (firebase-project-platform)
source = "cilly-yllic/firebase-project-platform/google"

# After (本リポジトリ)
source = "cilly-yllic/firebase-project-platform/google"  # Registry 名は変更なし
```

### GitHub Actions

```yaml
# Before
uses: MoooDoNE/terraform-google-firebase-project-platform/actions/dispatch@main
uses: MoooDoNE/terraform-gcp-project-factory/actions/dispatch@main

# After
uses: MoooDoNE/terraform-google-platform/actions/dispatch-firebase-platform@main
uses: MoooDoNE/terraform-google-platform/actions/dispatch-project-factory@main
```

---

## License

[Apache 2.0](LICENSE)

`modules/firebase-project-platform/` は元リポジトリで MIT License の下で公開されていたコードを含みます。
