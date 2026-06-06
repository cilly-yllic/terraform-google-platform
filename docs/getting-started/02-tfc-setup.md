# Step 2: Terraform Cloud セットアップ

Bootstrap で作成した WIF / SA を Terraform Cloud に接続し、Workspace が GCP リソースを管理できる状態にします。

---

## 前提条件

- Terraform Cloud Organization が作成済み
- [Step 1: Bootstrap](./01-bootstrap.md) が完了済み（`make bootstrap-print-env` の出力を手元に用意）

---

## 手順

### 1. Organization / Project の確認

Terraform Cloud にログインし、使用する Organization が存在することを確認します。
必要に応じて Project を作成してください（Workspace をグルーピングするため）。

### 2. project-bootstrap Workspace の作成

| 項目 | 値 |
|------|-----|
| Workspace 名 | `project-factory-{service}` (例: `project-factory-my-app`) |
| Execution Mode | Remote |
| VCS 連携 | 不要（API-driven） |

> Action A (`dispatch-project-bootstrap`) が自動で Workspace を作成・管理するため、手動作成は必須ではありません。初回実行前に Organization レベルの設定を整えておくだけで十分です。

### 3. Environment Variables の設定

[Step 1](./01-bootstrap.md) の `make bootstrap-print-env` で出力された値を、Organization レベルまたは Variable Set として設定します:

| Variable | Category | Value |
|----------|----------|-------|
| `TFC_GCP_PROVIDER_AUTH` | env | `true` |
| `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` | env | `terraform-project-factory@{project_id}.iam.gserviceaccount.com` |
| `TFC_GCP_WORKLOAD_PROVIDER_NAME` | env | `projects/{project_number}/locations/global/workloadIdentityPools/{pool_id}/providers/{provider_id}` |
| `GOOGLE_PROJECT` | env | Bootstrap Project ID |

> **Tip**: Variable Set を使えば、複数の Workspace に一括適用できます。

### 4. firebase-platform Workspace の確認

| 項目 | 値 |
|------|-----|
| Workspace 名 | `{service}-{environment}` (例: `my-app-dev`) |
| Execution Mode | Remote |

> こちらも Action B (`dispatch-firebase-platform`) が自動作成・管理します。

---

## Workspace 構造

| Workspace 名 | 用途 | Module | SA |
|--------------|------|--------|----|
| `project-factory-{service}` | per-service。全 env の Project を累積管理 | `project-bootstrap` | `terraform-project-factory` |
| `{service}-{env}` | per-env。Firebase Platform (terminal) | `firebase-project-platform` | `terraform-{service}-{env}` |

---

## 次のステップ

→ [Step 3: GitHub Actions 設定](./03-github-actions.md) — Action A / Action B の Workflow を設定します。

---

## 詳細リファレンス

- [Terraform Cloud — Dynamic Provider Credentials (GCP)](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/dynamic-provider-credentials/gcp-configuration)
- [docs/project-bootstrap/architecture.md](../project-bootstrap/architecture.md)
