# IAM Policy Design

bootstrap script (`scripts/bootstrap.sh`) および `terraform-gcp-project-factory` module が付与する IAM role の設計根拠と、意図的に付与しない role の例外条件をまとめる。

---

## bootstrap script が付与する role

### Organization または Folder レベル

| Role | 理由 |
|------|------|
| `roles/resourcemanager.projectCreator` | サービス用 GCP Project を作成するため |
| `roles/resourcemanager.projectIamAdmin` | 新規作成した Project に `terraform-{service}-{env}` SA への IAM を付与するため |

### Billing Account レベル

| Role | 理由 |
|------|------|
| `roles/billing.user` | Project に Billing Account を紐付けるため |

### infra-bootstrap Project レベル

| Role | 理由 |
|------|------|
| `roles/iam.serviceAccountAdmin` | `terraform-{service}-{env}` SA を `infra-bootstrap` 配下に作成・管理するため |
| `roles/iam.workloadIdentityPoolAdmin` | 各 SA に対する Workspace 単位の `workloadIdentityUser` binding を作成するため |

---

## bootstrap script が付与する WIF binding

`terraform-project-factory` SA に対して、Terraform Cloud Organization 全体からの impersonation を許可する:

```text
roles/iam.workloadIdentityUser
```

principalSet は `TFC_ORGANIZATION_NAME` に対応する attribute を使用。Workspace 単位の制限はこの段階では行わない。

理由:

- `terraform-project-factory` は複数の `project-factory-{service}` Workspace から共通で利用するため、組織レベル binding が運用上シンプル
- 各 `terraform-{service}-{env}` SA は後続の module 実行時に Workspace 単位の直接 WIF binding が作成される

---

## terraform-gcp-project-factory module が付与する role

### Project レベル (サービス Project)

`terraform-{service}-{env}` SA に対して以下を付与:

| Role | 理由 |
|------|------|
| `roles/resourcemanager.projectIamAdmin` | Firebase Platform module が self-grant で必要な role を追加付与するため |
| `roles/serviceusage.serviceUsageAdmin` | Firebase Platform module が必要な API を有効化するため |
| `roles/iam.serviceAccountAdmin` | サービス Project 内で追加 SA を管理するため |

Firebase 固有の詳細 role (`roles/firebase.admin`, `roles/datastore.owner` 等) は `terraform-google-firebase-project-platform` 側が `projectIamAdmin` 経由で self-grant する。本 module は Firebase 機能の詳細を知らない。

### Impersonation (WIF binding)

```text
roles/iam.workloadIdentityUser
```

Terraform Cloud Workspace `{tfc_workspace_name}` から `terraform-{service}-{env}` SA を **直接 WIF** で impersonate できるようにする。二段 impersonation は使わない。

principal:

```text
principalSet://iam.googleapis.com/projects/{bootstrap_project_number}/locations/global/workloadIdentityPools/{pool}/attribute.terraform_workspace/{tfc_workspace_name}
```

---

## 意図的に付与しない role と再付与条件

### `roles/iam.serviceAccountTokenCreator`

**不付与の理由:**

- TFC → 各 SA への impersonation は直接 WIF で行う方針。二段 impersonation を採用しない
- `terraform-project-factory` が他 SA の token を生成する経路はアーキテクチャ上存在しない
- 不要な権限を残すと「将来うっかり二段 impersonation 経路が紛れ込む」リスクがある

**再付与が必要になる条件:**

- 直接 WIF が利用できない事情が発生し、二段 impersonation 方式に切り替える場合
- Terraform code 内で `google_service_account_access_token` data source 経由の impersonation が必要になった場合
- いずれもアーキテクチャ判断の変更を伴うため、設計レビュー必須

**再付与時のスコープ:**

- infra-bootstrap Project レベル (`terraform-{service}-{env}` SA を対象 SA とする条件付き binding)

### `roles/serviceusage.serviceUsageAdmin` (bootstrap SA 側)

**不付与の理由:**

- `terraform-gcp-project-factory` module は API 有効化を行わない方針
- API 有効化はサービス Project 側で `terraform-{service}-{env}` SA が `terraform-google-firebase-project-platform` 実行時に行う
- bootstrap script が `infra-bootstrap` Project に必要 API を全て enable 済み
- 二重管理 (Project Factory 側と Firebase Platform 側で API を別々に enable) を避けたい

**再付与が必要になる条件:**

- `terraform-gcp-project-factory` module が `google_project_service` を扱う設計に変更された場合
- bootstrap 完了後に `infra-bootstrap` 自身で追加 API を有効化する必要が出た場合

**再付与時の最小スコープ:**

- サービス Project で必要 → Org/Folder レベル
- `infra-bootstrap` のみで必要 → infra-bootstrap Project レベルのみ
