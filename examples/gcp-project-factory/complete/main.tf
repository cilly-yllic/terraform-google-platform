module "project_factory" {
  source = "../../../modules/gcp-project-factory"

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

  bootstrap_project_id          = "my-infra-bootstrap"
  workload_identity_pool_id     = "my-terraform-pool"
  workload_identity_provider_id = "my-terraform-provider"
}
