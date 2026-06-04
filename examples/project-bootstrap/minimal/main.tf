module "project_factory" {
  source = "../../../modules/project-bootstrap"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"
}
