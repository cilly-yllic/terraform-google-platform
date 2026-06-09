# dispatch-tfc-project-bootstrap

`settings.yml` + branch 情報を元に Terraform Cloud の `project-factory-{service}` Workspace へ Run を起動する GitHub Action。

## Usage

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
  with:
    service: my-service
    environment: prd
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    billing_registry_repo: my-org/infra
    github_app_id: ${{ secrets.GH_APP_ID }}
    github_app_private_key: ${{ secrets.GH_APP_PRIVATE_KEY }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

## Inputs

| Name | Required | Default | Description |
|------|:--------:|---------|-------------|
| `service` | yes | — | Service name |
| `environment` | yes | — | Target environment (`dev`/`stg`/`prd`) |
| `settings_path` | no | `terraform/settings.yml` | Path to settings.yml in the calling repo |
| `tfc_org` | yes | — | Terraform Cloud organization name |
| `tfc_workspace_name` | no | `project-factory-{service}` | Workspace name pattern |
| `parent_organization_id` | no | — | GCP Org ID |
| `parent_folder_id` | no | — | GCP Folder ID |
| `bootstrap_project_id` | no | `infra-bootstrap` | Bootstrap project ID |
| `bootstrap_project_number` | yes | — | Bootstrap project number (numeric, for WIF resource name) |
| `workload_identity_pool_id` | no | `terraform-cloud` | WIF Pool ID |
| `workload_identity_provider_id` | no | `terraform-cloud` | WIF Provider ID |
| `billing_registry_repo` | yes | — | `owner/repo` holding `billing-accounts.yml` |
| `billing_registry_path` | no | `configs/billing-accounts.yml` | Path inside registry repo |
| `github_app_id` | yes | — | GitHub App ID |
| `github_app_private_key` | yes | — | GitHub App private key (PEM) |
| `tfc_token` | yes | — | Terraform Cloud API token |
| `enable_webhook_notification` | no | `false` | Create TFC notification for Phase 2 webhook |
| `cloud_run_webhook_url` | no | — | Cloud Run router URL (required if webhook enabled) |
| `cloud_run_webhook_secret` | no | — | HMAC secret for webhook |
| `module_version` | no | — | Version constraint for the Registry module written into the uploaded main.tf (e.g. `1.2.3`, `~> 1.0`). Empty = no pin (always latest). |
| `labels` | no | `""` | JSON array of JS RegExp pattern strings (例: `'["^tier:dev$","^region:apne1$"]'`)。指定時は settings.yml の env `labels` が全パターンに一致 (AND) しないと success-skip。詳細は [Environment gating](#environment-gating) |

## Outputs

| Name | Description |
|------|-------------|
| `run_id` | Terraform Cloud Run ID (empty when skipped) |
| `run_url` | URL to the Run in TFC UI (empty when skipped) |
| `workspace_id` | Terraform Cloud Workspace ID (empty when skipped) |
| `workspace_name` | Terraform Cloud Workspace name (empty when skipped) |
| `skipped` | `"true"` if the env was skipped (inactive status or labels mismatch), `"false"` otherwise |
| `skip_reason` | When skipped: `status_inactive` / `labels_mismatch`. Empty otherwise |

## Environment gating

実行前に settings.yml の env と Action input を突き合わせ、以下のいずれかでマッチしない場合は **success-skip** (`core.warning` + `outputs.skipped="true"` + `outputs.skip_reason=<reason>`)。matrix ループはそのまま完走する。

| Gate | 条件 | `skip_reason` |
|------|------|----------------|
| `status` | `environments.<env>.status: inactive` だと常に skip。設定だけ先行管理してインフラはまだ立てたくない env で使う (`status` 省略時は `active`) | `status_inactive` |
| `labels` (AND) | Action input `labels` が JSON 配列の RegExp で、各パターンが env の `labels` のいずれかにマッチする必要がある。input が空ならゲート無効 | `labels_mismatch` |

settings.yml 例:

```yaml
environments:
  prd-001:
    status: inactive   # 設定は保持しつつ provision は保留
    labels:
      - tier:prd
      - region:apne1
    billing_account_id: "AAAA-AAAA-AAAA"
  dev-001:
    labels:            # status 省略時は active
      - tier:dev
      - region:apne1
    billing_account_id: "BBBB-BBBB-BBBB"
```

workflow 例 (matrix で全 env を走らせ、tier:dev だけ実行):

```yaml
strategy:
  matrix:
    env: [dev-001, dev-002, stg-001, prd-001]
steps:
  - uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
    id: pf
    with:
      service: my-service
      environment: ${{ matrix.env }}
      labels: '["^tier:dev$"]'
      # ...
  - if: steps.pf.outputs.skipped != 'true'
    run: echo "ran: ${{ steps.pf.outputs.run_url }}"
```

`skipped` / `skip_reason` は早期失敗時にも `false` / 空文字で初期化されるので、後段 step の `if:` で安全に参照できる。パターンは `RegExp.test()` で評価され部分一致がデフォルト。完全一致したい場合は `^...$` で囲むこと。

## Notes

- main.tf / versions.tf は Action 内に同梱されたテンプレートを毎回 Terraform Cloud Configuration Version として upload します。Workspace 側に手動で VCS 連携や config を用意する必要はありません。テンプレートの module シェイプは `for_each = jsondecode(var.environments)` 形式で、`environments` 変数に env を追記していくことで service 単位の単一 workspace に複数 env を累積管理します。
- `parent` と `environments` は JSON 文字列 (`hcl: false`) として TFC Variable に格納されます。消費側の Terraform では `jsondecode()` で展開してください。
- `billing_registry_repo` は `owner/repo` 形式で指定してください。不正な形式の場合は明確なエラーメッセージが表示されます。
- `TFC_GCP_WORKLOAD_PROVIDER_NAME` には `bootstrap_project_number` (numeric) を使用します。GCP WIF リソース名は project number を要求するため、project ID ではなく project number を指定してください。

## Phase 1 (orchestrator 内 call)

```yaml
# infra-orchestrator の workflow から
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
  id: pf
  with:
    service: ${{ github.event.client_payload.service }}
    environment: ${{ github.event.client_payload.environment }}
    tfc_org: my-org
    bootstrap_project_number: "123456789012"
    billing_registry_repo: my-org/infra
    github_app_id: ${{ secrets.GH_APP_ID }}
    github_app_private_key: ${{ secrets.GH_APP_PRIVATE_KEY }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
# caller が polling
```

## Phase 2 (Project Repo から直接 call)

```yaml
# Project Repo の workflow から
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
  id: pf
  with:
    service: my-service
    environment: prd
    tfc_org: my-org
    bootstrap_project_number: "123456789012"
    billing_registry_repo: my-org/infra
    github_app_id: ${{ secrets.GH_APP_ID }}
    github_app_private_key: ${{ secrets.GH_APP_PRIVATE_KEY }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
    enable_webhook_notification: "true"
    cloud_run_webhook_url: https://router-xxxxx.run.app/tfc-webhook
    cloud_run_webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
# polling なし — TFC notification -> Cloud Run router が後続を駆動
```
