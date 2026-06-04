# dispatch-tfc-firebase-platform

A GitHub Action that starts a Terraform Cloud Run for the Firebase Platform.

Starting from the Project Repository's `terraform/settings.yml`, it fetches the project-factory workspace outputs and runs the **`{service}-{env}` workspace upsert → variable sync → Run create** flow in one shot.

For its position in the overall architecture, see [`docs/architecture.md`](../../docs/architecture.md).

> **Upstream docs**: [architecture.md](https://github.com/MoooDoNE/terraform-gcp-project-factory/blob/main/docs/architecture.md) / [related-components.md](https://github.com/MoooDoNE/terraform-gcp-project-factory/blob/main/docs/related-components.md)

This corresponds to **Action B** (`dispatch-tfc-firebase-platform`). Action A (`dispatch-tfc-project-factory`) lives in a separate repository and handles the project-factory stage.

<details><summary>Ja</summary>

Firebase Platform 用の Terraform Cloud Run を起動する GitHub Action。

Project Repository が `terraform/settings.yml` を起点に、project-factory workspace の outputs を取得し、`{service}-{env}` workspace を upsert → 変数同期 → Run 作成までを一括実行する。

全体アーキテクチャ上の位置づけは [`docs/architecture.md`](../../docs/architecture.md) を参照。

> **上流ドキュメント**: [architecture.md](https://github.com/MoooDoNE/terraform-gcp-project-factory/blob/main/docs/architecture.md) / [related-components.md](https://github.com/MoooDoNE/terraform-gcp-project-factory/blob/main/docs/related-components.md)

**Action B** (`dispatch-tfc-firebase-platform`) に対応する。Action A (`dispatch-tfc-project-factory`) は別リポジトリで管理され、project-factory ステージを担当する。

</details>

---

## Inputs

| Name | Description | Required | Default |
|------|-------------|:--------:|---------|
| `service` | Service name | yes | — |
| `environment` | Target environment (`dev` / `stg` / `prd`) | yes | — |
| `settings_path` | Path to settings.yml | no | `terraform/settings.yml` |
| `tfc_org` | Terraform Cloud organization name | yes | — |
| `project_factory_workspace` | Upstream project-factory workspace name pattern (`{service}` expansion) | no | `project-factory-{service}` |
| `target_workspace` | Workspace name pattern to create (`{service}`, `{environment}` expansion) | no | `{service}-{environment}` |
| `bootstrap_project_id` | GCP bootstrap project ID (for Workload Identity) | no | `infra-bootstrap` |
| `bootstrap_project_number` | GCP bootstrap project number (numeric, for the WIF path) | yes | — |
| `workload_identity_pool_id` | Workload Identity Pool ID | no | `terraform-cloud` |
| `workload_identity_provider_id` | Workload Identity Provider ID | no | `terraform-cloud` |
| `tfc_token` | Terraform Cloud API token | yes | — |
| `apply_policy` | Run apply policy: `auto` / `manual` / `env-based` | no | `env-based` |
| `enable_webhook_notification` | Whether to configure a Phase 2 webhook notification | no | `false` |
| `cloud_run_webhook_url` | Cloud Run router URL (required when webhook is on) | no | — |
| `cloud_run_webhook_secret` | HMAC secret (shared with the Cloud Run router) | no | — |

<details><summary>Ja</summary>

- `service` (required): サービス名
- `environment` (required): 対象環境 (`dev` / `stg` / `prd`)
- `settings_path` (default `terraform/settings.yml`): settings.yml のパス
- `tfc_org` (required): Terraform Cloud organization 名
- `project_factory_workspace` (default `project-factory-{service}`): 上流 project-factory workspace 名パターン
- `target_workspace` (default `{service}-{environment}`): 作成する workspace 名パターン
- `bootstrap_project_id` (default `infra-bootstrap`): GCP bootstrap project ID (Workload Identity 用)
- `bootstrap_project_number` (required): GCP bootstrap project number (数値, WIF パス用)
- `workload_identity_pool_id` (default `terraform-cloud`): Workload Identity Pool ID
- `workload_identity_provider_id` (default `terraform-cloud`): Workload Identity Provider ID
- `tfc_token` (required): Terraform Cloud API token
- `apply_policy` (default `env-based`): Run apply policy
- `enable_webhook_notification` (default `false`): Phase 2 webhook 通知を設定するか
- `cloud_run_webhook_url`: Cloud Run router URL (webhook 有効時必須)
- `cloud_run_webhook_secret`: HMAC secret (Cloud Run router と共有)

</details>

## Outputs

| Name | Description |
|------|-------------|
| `run_id` | Terraform Cloud Run ID |
| `run_url` | URL of the Run in the Terraform Cloud UI |
| `workspace_id` | Terraform Cloud Workspace ID |
| `workspace_name` | Terraform Cloud Workspace name |

---

## Apply policy

The `apply_policy` input controls Run auto-apply.

| Value | Behavior |
|-------|----------|
| `auto` | auto-apply across all environments |
| `manual` | manual approval across all environments |
| `env-based` (default) | dev = auto-apply, stg/prd = manual approval |

<details><summary>Ja</summary>

`apply_policy` input で Run の自動 apply を制御する。

- `auto` — 全環境で auto-apply
- `manual` — 全環境で手動承認
- `env-based` (default) — dev = auto-apply, stg/prd = 手動承認

</details>

---

## settings.yml structure

Example of the `firebase_platform` section the Action reads:

```yaml
service: my-app

environments:
  dev:
    project_id: my-app-dev
    firebase_platform:
      firebase: true
      firestore:
        location: asia-northeast1
      hosting: true
      storage: true
      authentication: true
      secret_manager: true
      cloud_tasks:
        location: asia-northeast1
  stg:
    project_id: my-app-stg
    firebase_platform:
      firebase: true
      firestore: true
      hosting: true
  prd:
    project_id: my-app-prd
    firebase_platform:
      firebase: true
      firestore: true
      hosting: true
      storage: true
```

Each feature accepts `null` (omitted) / `true` / `{ ... }` (custom config).

<details><summary>Ja</summary>

各機能は `null` (省略) / `true` / `{ ... }` (カスタム設定) で指定する。

</details>

---

## Examples

### Phase 1 (called from the orchestrator)

```yaml
jobs:
  firebase-platform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Dispatch Firebase Platform Run
        id: dispatch
        uses: cilly-yllic/terraform-google-firebase-project-platform/actions/dispatch@v1
        with:
          service: my-app
          environment: dev
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          tfc_token: ${{ secrets.TFC_TOKEN }}

      - name: Print Run URL
        run: echo "${{ steps.dispatch.outputs.run_url }}"
```

### Phase 2 (called directly from the Project Repo workflow)

```yaml
name: Firebase Platform Trigger
on:
  repository_dispatch:
    types: [firebase-platform-trigger]

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: cilly-yllic/terraform-google-firebase-project-platform/actions/dispatch@v1
        with:
          service: ${{ github.event.client_payload.service }}
          environment: ${{ github.event.client_payload.environment }}
          tfc_org: my-tfc-org
          bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
          apply_policy: env-based
          enable_webhook_notification: "true"
          cloud_run_webhook_url: ${{ secrets.WEBHOOK_URL }}
          cloud_run_webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
```

---

## Processing flow

1. Read `settings.yml` and extract the `environments[env].firebase_platform` section.
2. Use the TFC API to fetch `project_id` / `project_number` / `terraform_service_account_email` from the `project-factory-{service}` workspace outputs.
3. Upsert the `{service}-{env}` workspace (update if it exists, create otherwise).
4. Sync Terraform Variables — map each feature flag to an HCL variable in `null | true | object` form.
5. Sync Environment Variables (for TFC Dynamic Credentials).
6. Start the Run (applying the env-based apply policy).

<details><summary>Ja</summary>

1. `settings.yml` を読み込み、`environments[env].firebase_platform` セクションを抽出
2. TFC API で `project-factory-{service}` workspace の outputs から `project_id` / `project_number` / `terraform_service_account_email` を取得
3. `{service}-{env}` workspace を upsert (存在すれば update、なければ create)
4. Terraform Variables を同期 (各機能 flag を `null | true | object` 形式で HCL 変数にマッピング)
5. Environment Variables を同期 (TFC Dynamic Credentials 用)
6. Run を起動 (env 別 apply policy 適用)

</details>

> **⚠️ Full Workspace Management:** This Action fully manages the workspace's variables. Any variable the Action does not generate (e.g. manually added or set by other tooling) **will be deleted on every run**. Include manually-required variables in the `firebase_platform` section of `settings.yml`, or use a separate workspace.

> **ℹ️ API-driven Workspace:** This Action creates and manages an API-driven workspace with no VCS connection. GitHub Actions detects repo changes, sets Terraform variables based on settings.yml, and runs apply — no VCS link is needed.

<details><summary>Ja</summary>

- **Full Workspace Management:** この Action は workspace の変数を完全に管理する。Action が生成しない変数 (手動追加や他ツールで設定した変数) は **毎回削除される**。手動で設定が必要な変数がある場合は `settings.yml` の `firebase_platform` セクションに含めるか、別の workspace を使用すること
- **API-driven Workspace:** この Action は VCS 接続なしの API-driven workspace を作成・管理する。GitHub Actions 側がリポジトリの変更を検知し、settings.yml の値を元に Terraform 変数を設定して apply run を実行する設計のため、VCS 連携は不要

</details>
