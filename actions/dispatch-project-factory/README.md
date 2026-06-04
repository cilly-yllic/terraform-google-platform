# dispatch-tfc-project-factory

`settings.yml` + branch 情報を元に Terraform Cloud の `project-factory-{service}` Workspace へ Run を起動する GitHub Action。

## Usage

```yaml
- uses: MoooDoNE/terraform-gcp-project-factory/actions/dispatch@v1
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

## Outputs

| Name | Description |
|------|-------------|
| `run_id` | Terraform Cloud Run ID |
| `run_url` | URL to the Run in TFC UI |
| `workspace_id` | Terraform Cloud Workspace ID |
| `workspace_name` | Terraform Cloud Workspace name |

## Notes

- `parent` と `environments` は JSON 文字列 (`hcl: false`) として TFC Variable に格納されます。消費側の Terraform では `jsondecode()` で展開してください。
- `billing_registry_repo` は `owner/repo` 形式で指定してください。不正な形式の場合は明確なエラーメッセージが表示されます。
- `TFC_GCP_WORKLOAD_PROVIDER_NAME` には `bootstrap_project_number` (numeric) を使用します。GCP WIF リソース名は project number を要求するため、project ID ではなく project number を指定してください。

## Phase 1 (orchestrator 内 call)

```yaml
# infra-orchestrator の workflow から
- uses: MoooDoNE/terraform-gcp-project-factory/actions/dispatch@v1
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
- uses: MoooDoNE/terraform-gcp-project-factory/actions/dispatch@v1
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
