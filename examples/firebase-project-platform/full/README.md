# examples/full

Configuration with every feature on. Exercises Firebase core / extensions / GCP services / IAM (users + ci_service_account + service_accounts).

<details><summary>Ja</summary>

全機能 on の構成例。Firebase core / extensions / GCP services / IAM (users + ci_service_account + service_accounts) をすべて使う。

</details>

## What this example shows

- All **three patterns** for feature variables (`true` / `{ ... }` / list structures)
- `additional_apis` adding an API outside auto-derivation (`iap.googleapis.com`)
- Multiple users in `users` (editor + deploy / viewer)
- `ci_service_account` configured explicitly with `additional_roles`
- A deploy SA defined in `service_accounts`
- Multiple databases via `firestore.databases`
- Additional buckets + a Firestore-backup bucket via `storage.buckets` + `firestore_backup`
- Cloud SQL provisioned via `data_connect.cloud_sql`

<details><summary>Ja</summary>

- 機能変数の **3 パターン** (`true` / `{ ... }` / リスト構造) すべてを利用
- `additional_apis` で自動判定外の API (`iap.googleapis.com`) を追加
- `users` に複数ユーザー (editor + deploy / viewer)
- `ci_service_account` を `additional_roles` 付きで明示指定
- `service_accounts` で deploy 用追加 SA を作成
- `firestore.databases` で複数 DB を作成
- `storage.buckets` + `firestore_backup` で追加 bucket と backup bucket を作成
- `data_connect.cloud_sql` で Cloud SQL も含めて作成

</details>

## Resources you can expect to be created (excerpt)

| Category | Resource |
|----------|----------|
| API enablement | 30+ APIs (feature on/off + `iap.googleapis.com`) |
| Firebase core | Firebase project / Identity Platform / Firestore default + 2 databases (`analytics-db`, `logs-db`) / RTDB / Hosting site + Web App / Storage default + 2 buckets (`uploads`, `icons`) + Firestore-backup bucket / Data Connect service + Cloud SQL instance |
| Firebase extensions | FCM / Remote Config / App Check / Crashlytics / Performance / Analytics / Extensions all API-enabled |
| GCP services | Secret Manager / Cloud Tasks / Cloud Scheduler / Pub/Sub / Eventarc / Cloud Run / Cloud Functions all API-enabled |
| IAM | 2 user bindings + CI SA (`ci-deploy` + auto roles + `roles/viewer`) + additional SA (`app-runtime`) |

Details: [`main.tf`](./main.tf).

## How to use

### Prerequisites

- The GCP Project (`my-full-project`) is created
- Replace the Billing Account ID (`XXXXXX-XXXXXX-XXXXXX`) with a real one (or convert to `-var`)
- The Terraform-executing SA has sufficient permissions (`roles/owner`-equivalent, or each feature's `*.admin` exhaustively)

<details><summary>Ja</summary>

- GCP Project (`my-full-project`) が作成済み
- Billing Account ID (`XXXXXX-XXXXXX-XXXXXX`) を実際の値に書き換え (もしくは `-var` で渡す形に修正)
- Terraform 実行 SA に十分な権限 (`roles/owner` 相当、または各機能の `*.admin` を網羅)

</details>

### Run

```bash
cd examples/full
terraform init
terraform plan
terraform apply
```

`apply` enables 30+ APIs and creates dozens of resources — expect 5–15 minutes.

<details><summary>Ja</summary>

`apply` は 30+ API 有効化と数十リソースの作成を伴うため、5〜15 分程度かかる。

</details>

### Caveats

- A **Cloud SQL instance** is created. Note the cost (`db-f1-micro`).
- It is created with `deletion_protection = false`, so `destroy` will remove it.
- **Identity Platform config** is a **singleton per GCP Project** and cannot be deleted from the Console after creation.
- Storage / Firestore are created with **deny-all initial rules**. Deploy production rules via Firebase CLI.

<details><summary>Ja</summary>

- **Cloud SQL instance** が作成される。料金が発生する点に注意 (`db-f1-micro`)
- **deletion_protection = false** で作成されるため、`destroy` で消える
- **Identity Platform config** は **GCP Project に 1 つの singleton**。一度作成すると Console から削除できない
- Storage / Firestore は **deny-all 初期 rules** で作成される。本番ルールは Firebase CLI でデプロイする

</details>

### Tear down

```bash
terraform destroy
```

Tearing down **after writing data to Cloud SQL or Firestore** should be avoided in practice. Assume tear-down right after the trial.

<details><summary>Ja</summary>

Cloud SQL や Firestore に **データを書き込んだ後の destroy** は実用上避けるべき。試用後すぐに destroy する想定。

</details>

## Values to edit before real use

Rewrite these in `main.tf` before running for real:

- `project_id` (`"my-full-project"` → real project ID)
- `billing_account` (`"XXXXXX-XXXXXX-XXXXXX"` → real billing account ID)
- `users[*].email` (replace the `example.com` placeholders)
- `hosting[].site_id` / `data_connect.service_id` (values that require global uniqueness)

<details><summary>Ja</summary>

`main.tf` の以下を実利用時に書き換える:

- `project_id` (`"my-full-project"` → 実 project ID)
- `billing_account` (`"XXXXXX-XXXXXX-XXXXXX"` → 実 billing account ID)
- `users[*].email` (テンプレートの `example.com` を実 email に)
- `hosting[].site_id` / `data_connect.service_id` (グローバル一意である必要のあるもの)

</details>

## Related documentation

- [docs/variables-reference.md](../../docs/variables-reference.md) — Complete reference for each feature variable
- [docs/api-auto-enablement.md](../../docs/api-auto-enablement.md) — Feature → auto-enabled API mapping
- [docs/service-accounts.md](../../docs/service-accounts.md) — CI SA / additional SA operations

<details><summary>Ja</summary>

- [docs/variables-reference.md](../../docs/variables-reference.md) — 各機能変数の完全リファレンス
- [docs/api-auto-enablement.md](../../docs/api-auto-enablement.md) — 機能 → 自動有効化 API
- [docs/service-accounts.md](../../docs/service-accounts.md) — CI SA / 追加 SA の運用

</details>
