# Minimal Example

必須 input のみを指定するシンプルな利用例。

## Usage

```hcl
module "project_factory" {
  source  = "cilly-yllic/platform/google//modules/project-bootstrap"
  version = "~> 1.0"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"

  # infra-bootstrap project の数値 project number (default 無しの必須 input)。
  # 作成する Terraform SA の WIF principalSet パスの組み立てに使う。
  bootstrap_project_number = "123456789012"
}
```

`org_id` の代わりに `folder_id` を指定することもできます。少なくとも一方が必要です。

## Inputs

| Name | Required | Description |
|------|----------|-------------|
| `project_id` | yes | GCP Project ID |
| `project_name` | yes | GCP Project display name |
| `billing_account_id` | yes | Billing Account ID |
| `terraform_service_account_id` | yes | Terraform SA ID (≤ 30 chars) |
| `tfc_workspace_name` | yes | TFC Workspace name for WIF impersonation |
| `bootstrap_project_number` | yes | infra-bootstrap project の数値 project number (WIF principalSet 用) |
| `org_id` / `folder_id` | one of | Organization ID または Folder ID。少なくとも一方が必要 (`folder_id` 優先) |
