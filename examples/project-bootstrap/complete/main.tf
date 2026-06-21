module "project_factory" {
  source = "../../../modules/project-bootstrap"

  # --- Required ---
  project_id                   = "myservice-prd-001"
  project_name                 = "My Service Production"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-myservice-prd"
  tfc_workspace_name           = "myservice-prd"

  # --- Project placement (at least one of org_id / folder_id is required) ---
  org_id    = "123456789012"
  folder_id = "987654321098" # Takes precedence over org_id when both are set

  # --- Optional ---
  deletion_policy = "PREVENT"

  labels = {
    env     = "prd"
    service = "myservice"
  }

  # infra-bootstrap project の数値 project number (WIF principalSet パス組み立て用、必須)。
  bootstrap_project_id          = "my-infra-bootstrap"
  bootstrap_project_number      = "123456789012"
  workload_identity_pool_id     = "my-terraform-pool"
  workload_identity_provider_id = "my-terraform-provider"
}
