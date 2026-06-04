# terraform-google-platform

GCP / Firebase プロジェクトの作成・設定を一元管理する Terraform Module および GitHub Actions のモノリポ。

以下の 2 つのリポジトリを統合したものです:

- [`terraform-google-firebase-project-platform`](https://github.com/cilly-yllic/terraform-google-firebase-project-platform) — Firebase / GCP サービスリソースの有効化・設定
- `project-bootstrap` — GCP Project 作成・SA 管理・WIF 設定

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

### `modules/project-bootstrap`

GCP Project 作成と Terraform 実行用 Service Account 作成・管理を行うモジュール。

Terraform Registry: `cilly-yllic/project-bootstrap/google`

```hcl
module "project_bootstrap" {
  source = "cilly-yllic/project-bootstrap/google"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"
}
```

詳細: [`modules/project-bootstrap/`](./modules/project-bootstrap/) / [docs](./docs/project-bootstrap/)

---

## GitHub Actions

| Action | Path | Usage |
|--------|------|-------|
| dispatch-tfc-firebase-platform | `actions/dispatch-firebase-platform/` | `uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main` |
| dispatch-tfc-project-bootstrap | `actions/dispatch-project-bootstrap/` | `uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main` |

---

## Cloud Run Router

TFC notification を受けて GitHub `repository_dispatch` を発火する Cloud Run service。

詳細: [`cloud-run-router/`](./cloud-run-router/)

---

## Bootstrap (project-bootstrap)

`infra-bootstrap` Project / Service Account / WIF を構築するための bootstrap script:

```bash
cp scripts/bootstrap.example.env .env
vi .env

make bootstrap-check   # 事前確認
make bootstrap         # リソース作成
```

詳細: [`scripts/`](./scripts/) / [docs/project-bootstrap/bootstrap.md](./docs/project-bootstrap/bootstrap.md)

---

## Examples

| Module | Example | Path |
|--------|---------|------|
| firebase-project-platform | minimal | [`examples/firebase-project-platform/minimal/`](./examples/firebase-project-platform/minimal/) |
| firebase-project-platform | full | [`examples/firebase-project-platform/full/`](./examples/firebase-project-platform/full/) |
| project-bootstrap | minimal | [`examples/project-bootstrap/minimal/`](./examples/project-bootstrap/minimal/) |
| project-bootstrap | complete | [`examples/project-bootstrap/complete/`](./examples/project-bootstrap/complete/) |

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
│   └── project-bootstrap/            # Project 作成 Module
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       ├── data.tf
│       ├── locals.tf
│       └── modules/                  # Sub-modules (project, service-account, iam)
├── actions/
│   ├── dispatch-firebase-platform/   # GitHub Action: TFC dispatch (firebase)
│   └── dispatch-project-bootstrap/   # GitHub Action: TFC dispatch (project-bootstrap)
├── cloud-run-router/                 # Cloud Run: TFC notification → repository_dispatch
├── scripts/                          # Bootstrap scripts (project-bootstrap)
├── examples/
│   ├── firebase-project-platform/
│   │   ├── minimal/
│   │   └── full/
│   └── project-bootstrap/
│       ├── minimal/
│       └── complete/
├── docs/
│   ├── firebase-project-platform/    # Firebase Module ドキュメント
│   └── project-bootstrap/            # Project Bootstrap ドキュメント
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
| Project Bootstrap Architecture | [docs/project-bootstrap/architecture.md](./docs/project-bootstrap/architecture.md) |
| Project Bootstrap Guide | [docs/project-bootstrap/bootstrap.md](./docs/project-bootstrap/bootstrap.md) |
| IAM Policy Design | [docs/project-bootstrap/design/iam-policy.md](./docs/project-bootstrap/design/iam-policy.md) |
| WIF Attribute Mapping | [docs/project-bootstrap/design/wif-attribute-mapping.md](./docs/project-bootstrap/design/wif-attribute-mapping.md) |

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

```hcl
# project-bootstrap
source = "cilly-yllic/project-bootstrap/google"
```

### GitHub Actions

```yaml
uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
```

---

## License

[Apache 2.0](LICENSE)

`modules/firebase-project-platform/` は元リポジトリで MIT License の下で公開されていたコードを含みます。
