# terraform-google-platform

GCP / Firebase プロジェクトの作成・設定を一元管理する Terraform Module および GitHub Actions のモノリポ。

主なコンポーネント:

- [`modules/firebase-project-platform/`](./modules/firebase-project-platform/) — Firebase Platform 化（Firebase / GCP リソース・API・IAM）
- [`modules/project-bootstrap/`](./modules/project-bootstrap/) — GCP Project / SA / IAM の作成（project factory）
- [`modules/compute-host-platform/`](./modules/compute-host-platform/) — VM を置くプロジェクトの基盤（VPC・ファイアウォール・Cloud NAT・最小権限の IAM）

---

## Getting Started

本リポジトリの全コンポーネントを使って GCP Project 作成から Firebase Platform 構築までを行うエンドツーエンド導入ガイドを用意しています。

→ **[docs/getting-started/](./docs/getting-started/)** — 前提条件・各ステップの詳細手順・通し検証まで

---

## Terraform Modules

本リポジトリは Terraform Registry に **1 entry (`cilly-yllic/platform/google`)** として publish され、配下の `modules/<name>` を **subdirectory 参照**で利用する形式です:

```
registry.terraform.io/modules/cilly-yllic/platform/google
└── modules/
    ├── firebase-project-platform   ← サブモジュール
    ├── project-bootstrap            ← サブモジュール
    └── compute-host-platform        ← サブモジュール
```

### `modules/firebase-project-platform`

Firebase / GCP プロジェクトに必要なリソースを **feature variables** で選択的に作成する共通モジュール。

```hcl
module "firebase_platform" {
  source  = "cilly-yllic/platform/google//modules/firebase-project-platform"
  version = "~> 1.0"   # 1.x の正式 release に追従 (rc tag は pre-release のため自動選択されない)

  project_id = "my-project-id"
  region     = "asia-northeast1"

  firebase  = true
  firestore = true
  apps = [
    { name = "main", type = "web" },
  ]
  hosting = [
    { site_id = "my-project-web" },
  ]
}
```

詳細: [`modules/firebase-project-platform/`](./modules/firebase-project-platform/) / [docs](./docs/firebase-project-platform/)

### `modules/project-bootstrap`

GCP Project 作成と Terraform 実行用 Service Account 作成・管理を行うモジュール。

```hcl
module "project_bootstrap" {
  source  = "cilly-yllic/platform/google//modules/project-bootstrap"
  version = "~> 1.0"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"
}
```

詳細: [`modules/project-bootstrap/`](./modules/project-bootstrap/) / [docs](./docs/project-bootstrap/)

### `modules/compute-host-platform`

Firebase のプロジェクトとは別の「VM を置くプロジェクト」（compute host）に、VM 用のネットワークと最小権限の IAM を作るモジュール。VM そのものは作らない（利用側のアプリが実行時に作る）。プロジェクトは `project-bootstrap` で作る。

```hcl
module "compute_host" {
  source  = "cilly-yllic/platform/google//modules/compute-host-platform"
  version = "~> 2.1"

  project_id = "example-host-dev-001"
  region     = "asia-northeast1"

  network   = { name = "vm", subnets = [{ name = "vm-asia-northeast1", cidr = "10.10.0.0/20" }] }
  cloud_nat = { router_name = "vm-router", nat_name = "vm-nat" }
  firewall_rules = [
    { name = "deny-internal-egress", direction = "EGRESS", action = "deny", priority = 900,
      ranges = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"] },
  ]

  service_accounts = [{ account_id = "vm-runtime" }]
  custom_roles = [{
    role_id     = "vmManager"
    title       = "VM manager"
    permissions = ["compute.instances.create", "compute.instances.start", "compute.instances.stop"]
  }]
  iam_bindings = [
    { name = "manager-vms", role = "custom:vmManager",
      members = { manager = "serviceAccount:manager@other-project.iam.gserviceaccount.com" } },
  ]
  service_account_iam = [
    { name = "manager-acts-as-runtime", service_account = "vm-runtime", role = "roles/iam.serviceAccountUser",
      members = { manager = "serviceAccount:manager@other-project.iam.gserviceaccount.com" } },
  ]
}
```

- `"custom:<role_id>"` は `custom_roles` のロール、`"sa:<account_id>"` はこのモジュールの SA を指す
- IAM は非排他（ほかの付与を消さない）。付与ごとに `name`、相手ごとにラベル（`members` の key）を付ける。これが付与の識別子になるので、並べ替え・追加で既存の付与を作り直さず、相手の値（別の資源で作る SA のメールなど）が apply まで決まらなくても plan できる
- `iam_bindings` の条件は、同じ相手・同じ role の条件なしの付与を狭めない。同じ付与を `iam_bindings` と `service_accounts` の `roles` に重ねると断る
- ファイアウォールの `ranges` は 1 つ以上（すべてなら `0.0.0.0/0` を明示する）
- Cloud NAT が効くのは同じリージョンのサブネットだけ。違うリージョンのサブネットがあると断る
- カスタムロールを外して apply すると削除される。GCP は削除したロールの `role_id` を一定期間（約 37 日）再利用できないので、戻すときは `gcloud iam roles undelete` で復元してから `terraform import` する（新しい `role_id` にしてもよい）
- プロジェクト単位の組織のポリシー（外部 IP の禁止など）は、このモジュールの対象外
- settings.yml から使う Action（`dispatch-compute-host`）は後で足す

詳細: [`modules/compute-host-platform/`](./modules/compute-host-platform/)

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

# Action B は Cloud Run Router の client_payload.environments を *そのまま* 渡せる
# (Router が compact JSON 文字列で送るため toJSON() を被せると二重エンコードになり NG)
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: ${{ github.event.client_payload.service }}
    environments: ${{ github.event.client_payload.environments }}
    tfc_org: my-tfc-org
    bootstrap_project_number: ${{ vars.BOOTSTRAP_PROJECT_NUMBER }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

> `bootstrap_project_number` は numeric な project number で機密ではないため、Secret ではなく **GitHub Variable** (`vars.*`) で渡すのが実運用パターン。
>
> Phase 2 (Webhook) を使う場合は Action A に `enable_webhook_notification: "true"` / `cloud_run_webhook_url` / `cloud_run_webhook_secret` を追加すると、A の Run 完了時に Cloud Run Router 経由で B が自動 dispatch される。詳細は [Getting Started: GitHub Actions](./docs/getting-started/03-github-actions.md#phase-2-webhook-連携を有効にする)。

詳細: [Action A README](./actions/dispatch-project-bootstrap/README.md) / [Action B README](./actions/dispatch-firebase-platform/README.md) / [Getting Started: GitHub Actions](./docs/getting-started/03-github-actions.md)

---

## Cloud Run Router

TFC notification を受けて GitHub `repository_dispatch` を発火する Cloud Run service。

- ソースコードと仕様: [`cloud-run-router/`](./cloud-run-router/)
- デプロイ用 reference workflow: [`examples/cloud-run-router-deploy/`](./examples/cloud-run-router-deploy/)
  (推奨は **private な deploy 専用 repo** にコピーして使用)
- 認証 / IAM の事前セットアップ: [`scripts/README.md` — Cloud Run router deploy 拡張](./scripts/README.md#cloud-run-router-deploy-拡張-opt-in)

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

| 種別 | Path | 内容 |
|-----|------|------|
| Terraform Module | [`examples/firebase-project-platform/minimal/`](./examples/firebase-project-platform/minimal/) | firebase-project-platform 最小構成 |
| Terraform Module | [`examples/firebase-project-platform/full/`](./examples/firebase-project-platform/full/) | firebase-project-platform フル構成 |
| Terraform Module | [`examples/project-bootstrap/minimal/`](./examples/project-bootstrap/minimal/) | project-bootstrap 最小構成 |
| Terraform Module | [`examples/project-bootstrap/complete/`](./examples/project-bootstrap/complete/) | project-bootstrap 完全構成 |
| GitHub Actions | [`examples/cloud-run-router-deploy/`](./examples/cloud-run-router-deploy/) | cloud-run-router の deploy workflow (reference, 自リポにコピーして使用) |

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
│   ├── project-bootstrap/
│   │   ├── minimal/
│   │   └── complete/
│   └── cloud-run-router-deploy/      # cloud-run-router deploy workflow (reference)
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

### Terraform Module の source 移行 (v0.0.0-rc6 以降)

旧 Registry entry (個別 publish) から **新 unified entry (subdirectory 参照)** に統一しました。利用側 main.tf の `source` を以下のように書き換えてください:

```hcl
# Before (旧個別 Registry entry — publish されていなかったため実際は動かなかった)
source = "cilly-yllic/firebase-project-platform/google"
source = "cilly-yllic/project-bootstrap/google"

# After (本リポジトリの統合 Registry entry)
source  = "cilly-yllic/platform/google//modules/firebase-project-platform"
version = "~> 1.0"

source  = "cilly-yllic/platform/google//modules/project-bootstrap"
version = "~> 1.0"
```

### GitHub Actions の uses 行は変わらず

```yaml
uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
```

### Action template が自動生成する main.tf

Action B / A が TFC workspace に upload する main.tf も自動で新 source 形式 (`cilly-yllic/platform/google//modules/<name>`) を出力します (PR を merge して新 tag を切れば反映)。

---

## Terraform Registry Publish 手順 (リポジトリ管理者向け)

1. https://registry.terraform.io/sign-in で GitHub アカウントでサインイン
2. `Publish` → `Module` → 該当 repo (`cilly-yllic/terraform-google-platform`) を選択
3. Registry 上の module 名は `cilly-yllic/platform/google` として登録される (repo 名 `terraform-google-platform` から自動派生)
4. 以降は新 tag (`v0.0.0-rcN` 等) を push するたびに自動 ingest される
5. 配下のサブモジュールは利用側の `source` で `//modules/<name>` 参照することで自動的に解決される

---

## License

[Apache 2.0](LICENSE)

`modules/firebase-project-platform/` は元リポジトリで MIT License の下で公開されていたコードを含みます。
