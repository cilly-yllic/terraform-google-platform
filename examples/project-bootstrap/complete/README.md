# Complete Example

全 input を指定し、labels / WIF / folder 配置を含む完全な利用例。

## Usage

```hcl
module "project_factory" {
  source  = "cilly-yllic/platform/google//modules/project-bootstrap"
  version = "~> 0.0"

  project_id                   = "myservice-prd-001"
  project_name                 = "My Service Production"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-myservice-prd"
  tfc_workspace_name           = "myservice-prd"

  org_id    = "123456789012"
  folder_id = "987654321098"  # Takes precedence over org_id

  deletion_policy = "PREVENT"

  labels = {
    env     = "prd"
    service = "myservice"
  }

  bootstrap_project_id          = "my-infra-bootstrap"
  bootstrap_project_number      = "123456789012" # 必須: WIF principalSet パス組み立て用
  workload_identity_pool_id     = "my-terraform-pool"
  workload_identity_provider_id = "my-terraform-provider"
}
```

## Inputs

すべての variable を指定した例です。各 variable の詳細は [root README](../../README.md) を参照してください。
