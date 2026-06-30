# Quickstart (最低限手順)

0 から「サービス用 GCP Project を作って Firebase Platform を構築する」までの最短手順です。
各ステップの詳細・前提・トラブルシュートは右端の「詳細」リンク先を参照してください。

> 記号: 🔹=必須 / ⏸️=オプション / 🔁=再構築(bootstrap 作り直し)時に再実行が必要

| # | 操作 | コマンド / 場所 | 詳細 |
|---|------|----------------|------|
| 1 🔹 | `.env` をテンプレからコピー | `scripts/bootstrap.sh --init=env`（または `cp scripts/bootstrap.example.env .env`） | [01-bootstrap](./01-bootstrap.md#1-環境変数ファイルの準備) |
| 2 🔹 | 必須項目を入力 | `vi .env`（下記「`.env` 最低限」参照） | [bootstrap.example.env](../../scripts/bootstrap.example.env) |
| 3 🔹🔁 | infra-bootstrap project / Factory SA / WIF を作成 | `make bootstrap` → `make bootstrap-print-env` | [01-bootstrap](./01-bootstrap.md#4-リソース作成) |
| 4 🔹🔁 | 消費側 repo へ Secrets/Variables を同期 | `make github-sync-apply` | [01-bootstrap](./01-bootstrap.md#6-消費側-repo-へ-secrets--variables-を同期-github-sync) |
| 5 🔹 | サービス用 Billing Account を用意し ID を `.env` に追記 | 既存があればその ID を `SERVICE_BILLING_ACCOUNT_IDS` に。新規作成は `make create-billing-account` | [00-billing-account](./00-billing-account.md) |
| 6 🔹🔁 | Factory SA に billing.user を付与 | `make grant-billing`（または `make grant-billing BILLING=<id>`） | [01-bootstrap](./01-bootstrap.md#7-billing-account-へ-factory-sa-を-grant-grant-billing) |
| 7 ⏸️🔁 | TFC Notification HMAC を初期化（Phase 2 webhook 自動連鎖を使う場合） | GitHub Actions `Initialize / Rotate TFC_NOTIFICATION_SECRET`（rotate=false / 既存ありは true） | [04-cloud-run-router](./04-cloud-run-router.md#a-4-deploy-workflow-を起動) |
| 8 ⏸️🔁 | Cloud Run Router をデプロイ（Phase 2 webhook を使う場合） | GitHub Actions `Deploy cloud-run-router`（手順 7 で自動起動 / 手動 dispatch も可） | [04-cloud-run-router](./04-cloud-run-router.md) |
| 9 🔹 | Action A 実行（サービス project 作成） | service repo の `provision-project` を `workflow_dispatch`（`service` / `environment`） | [05-end-to-end](./05-end-to-end.md#1-action-a-dispatch-project-bootstrap-の実行) |
| 10 🔹 | Action B 実行（Firebase Platform 構成） | Phase2=自動連鎖 / Phase1=`configure-platform` を手動（`environments`） | [05-end-to-end](./05-end-to-end.md#3-action-b-dispatch-firebase-platform-の実行) |
| 11 ⏸️ | アプリのデプロイ | `firebase deploy --only firestore,functions,apphosting,hosting` | [app-hosting](../firebase-project-platform/app-hosting.md) |

> **Phase 1 / Phase 2 の違い**: 手順 7・8 は **Phase 2(webhook 自動連鎖)** 用です。これらを省くと **Phase 1(手動)** 運用になり、Action A 完了後に Action B を手動実行します（手順 10）。まず Phase 1 で通し、後から Phase 2 を足すのが安全です。

---

## `.env` 最低限（手順 2）

```bash
# --- bootstrap project 本体 (必須) ---
BOOTSTRAP_PROJECT_ID="mdn-infra-bootstrap-003"
BOOTSTRAP_PROJECT_NAME="infra bootstrap"
BOOTSTRAP_BILLING_ACCOUNT_ID="01CAAA-CF1712-505329"   # bootstrap project 用 billing
TERRAFORM_PROJECT_FACTORY_SA_ID="terraform-project-factory"
WORKLOAD_IDENTITY_POOL_ID="terraform-cloud"
WORKLOAD_IDENTITY_PROVIDER_ID="terraform-cloud"
TFC_ORGANIZATION_NAME="MoooDoNE"

# --- 配置 (folder 推奨) ---
ORGANIZATION_ID="<org numeric id>"
BOOTSTRAP_FOLDER_NAME="infra"        # find-or-create して BOOTSTRAP_FOLDER_ID を自動解決

# --- github-sync (手順 4) ---
GITHUB_REPOSITORY="MoooDoNE/infrastructure"     # orchestrator repo
SERVICE_GITHUB_REPOS="MoooDoNE/cmonoth"         # 各 service repo に BOOTSTRAP_PROJECT_NUMBER を配る

# --- grant-billing (手順 6) ---
SERVICE_BILLING_ACCOUNT_IDS="01CAAA-CF1712-505329"   # サービス project 用 billing (空白区切りで複数可)

# --- Cloud Run Router を GitHub Actions でデプロイする場合 (手順 7-8) ---
ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"            # deploy/runtime SA + github WIF provider + Secret container を作成
```

全項目は [`scripts/bootstrap.example.env`](../../scripts/bootstrap.example.env) を参照。

---

## 再構築（bootstrap project を作り直した）時の注意

bootstrap project を新規 ID で作り直すと **project number が変わる**ため、🔁 のステップ（3・4・6・7・8）を再実行する必要があります。特に:

- **手順 4 `make github-sync-apply`**: `GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_DEPLOY_SERVICE_ACCOUNT` / `GCP_RUNTIME_SERVICE_ACCOUNT`（Secret）と `BOOTSTRAP_PROJECT_NUMBER`（Variable, service repo にも）を新値で再同期。これを忘れると Cloud Run Router deploy が WIF audience 不正で落ちる。
- **手順 6 `make grant-billing`**: 新 Factory SA に billing.user を再付与。忘れると Action A が `billing.resourceAssociations.create` 権限不足で落ちる。
- soft-delete 中（30日以内）の同 ID project は `gcloud projects undelete <id>` で番号据え置き復元も可能（その場合 number 不変なので再同期の手間が減る）。

---

## 次に読む

- 通しの詳細手順 → [Getting Started README](./README.md)
- エンドツーエンド検証 / トラブルシュート → [05-end-to-end.md](./05-end-to-end.md#トラブルシューティング)
