module "project_factory" {
  source = "../../../modules/project-bootstrap"

  project_id                   = "example-prd-001"
  project_name                 = "Example Production"
  org_id                       = "123456789012"
  billing_account_id           = "XXXXXX-XXXXXX-XXXXXX"
  terraform_service_account_id = "terraform-example-prd"
  tfc_workspace_name           = "example-prd"

  # 作成する SA の WIF principalSet パスを組み立てるための infra-bootstrap
  # project の **数値** project number。default が無い必須 input。
  # 値は bootstrap 環境を作った際の output (or GCP Console の Project number) で確認する。
  bootstrap_project_number = "123456789012"
}
