# terraform-google-platform

GCP / Firebase プロジェクトの作成・設定を一元管理する Terraform Module および GitHub Actions のモノリポ。

以下の 2 つの旧リポジトリ（廃止済み）を統合したものです:

- `terraform-google-firebase-project-platform` → [`modules/firebase-project-platform/`](./modules/firebase-project-platform/)
- `terraform-gcp-project-factory` → [`modules/project-bootstrap/`](./modules/project-bootstrap/)

---

## Getting Started

本リポジトリの全コンポーネントを使って GCP Project 作成から Firebase Platform 構築までを行うエンドツーエンド導入ガイドを用意しています。

→ **[docs/getting-started/](./docs/getting-started/)** — 前提条件・各ステップの詳細手順・通し検証まで

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

| Action | Path | 担当 | 主な機能 |
|--------|------|------|------|
| dispatch-tfc-project-bootstrap (A) | `actions/dispatch-project-bootstrap/` | GCP Project / SA / WIF の bootstrap | `environments` map に複数 env を蓄積し 1 Run で `for_each` 展開 |
| dispatch-tfc-firebase-platform (B) | `actions/dispatch-firebase-platform/` | Firebase Platform リソースの構築 | env ごとに `{service}-{env}` workspace を作成し逐次 Run |

両 Action は同一の `settings.yml` を読み、env 選別ロジックも共通（status / labels gate）。input shape は用途に合わせて異なる:

| Action | env 入力 | labels 入力 |
|---|---|---|
| A | `environment: prd-001` (単数文字列、optional) | `labels: '["^tier:dev$"]'` (JSON 配列、optional) |
| B | `environments: '["prd-001","dev-002"]'` (JSON 配列、optional) | `labels: '["^tier:dev$"]'` (JSON 配列、optional) |

どちらの Action も「`environment`/`environments` か `labels` の少なくとも一方」を必須とする。`settings.yml` 直下の `retained_envs` は廃止時の安全網で、`environments:` から消えた env でも `retained_envs` に書かれていれば GCP リソース (A) / TFC workspace (B) を残す。

```yaml
# .github/workflows/bootstrap.yml — labels で複数 env を一括 bootstrap
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
  with:
    service: my-service
    labels: '["^tier:dev$"]'    # tier:dev の env を 1 Run でまとめて
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    parent_organization_id: "999999999999"
    tfc_token: ${{ secrets.TFC_TOKEN }}

# Action B も Cloud Run Router の environments 出力をそのまま渡せる
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: ${{ github.event.client_payload.service }}
    environments: ${{ toJSON(github.event.client_payload.environments) }}
    tfc_org: my-tfc-org
    bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

詳細: [Action A README](./actions/dispatch-project-bootstrap/README.md) / [Action B README](./actions/dispatch-firebase-platform/README.md) / [Getting Started: GitHub Actions](./docs/getting-started/03-github-actions.md)

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

### Billing Account 作成

Billing Account を master billing account 配下に新規作成するスクリプト:

```bash
cp scripts/create-billing-account.example.env .env.billing
vi .env.billing

make create-billing-account-check      # 事前確認
make create-billing-account            # Billing Account 作成
make create-billing-account-print-env  # 作成された ID を確認
```

> **注意**: master billing account (Reseller / Channel Partner) を持つ場合のみ利用可能です。

詳細: [`scripts/`](./scripts/) / [docs/project-bootstrap/create-billing-account.md](./docs/project-bootstrap/create-billing-account.md)

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
│   ├── getting-started/              # エンドツーエンド導入ガイド
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
| **Getting Started** | [docs/getting-started/](./docs/getting-started/) |
| Firebase Platform Architecture | [docs/firebase-project-platform/architecture.md](./docs/firebase-project-platform/architecture.md) |
| Firebase Variables Reference | [docs/firebase-project-platform/variables-reference.md](./docs/firebase-project-platform/variables-reference.md) |
| Firebase Upgrade Guide | [docs/firebase-project-platform/upgrade-guide.md](./docs/firebase-project-platform/upgrade-guide.md) |
| Project Bootstrap Architecture | [docs/project-bootstrap/architecture.md](./docs/project-bootstrap/architecture.md) |
| Project Bootstrap Guide | [docs/project-bootstrap/bootstrap.md](./docs/project-bootstrap/bootstrap.md) |
| Billing Account 作成ガイド | [docs/project-bootstrap/create-billing-account.md](./docs/project-bootstrap/create-billing-account.md) |
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
