# Minimal Example

必須 input のみを指定するシンプルな利用例。

## Usage

```hcl
module "project_factory" {
  source  = "cilly-yllic/platform/google//modules/project-bootstrap"
  version = "~> 0.1"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"
}
```

`org_id` の代わりに `folder_id` を指定することもできます。少なくとも一方が必要です。

## Inputs

| Name | Description |
|------|-------------|
| `project_id` | GCP Project ID |
| `project_name` | GCP Project display name |
| `org_id` | Organization ID (or use `folder_id`) |
| `billing_account_id` | Billing Account ID |
| `terraform_service_account_id` | Terraform SA ID |
| `tfc_workspace_name` | TFC Workspace name for WIF |
