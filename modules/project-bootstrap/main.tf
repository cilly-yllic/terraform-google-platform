module "project" {
  source = "./modules/project"

  project_id         = var.project_id
  project_name       = var.project_name
  org_id             = var.org_id
  folder_id          = var.folder_id
  billing_account_id = var.billing_account_id
  labels             = var.labels
  deletion_policy    = var.deletion_policy
}

module "service_account" {
  source = "./modules/service-account"

  bootstrap_project_id = var.bootstrap_project_id
  service_account_id   = var.terraform_service_account_id
}

module "iam" {
  source = "./modules/iam"

  project_id                = module.project.project_id
  service_account_email     = module.service_account.email
  service_account_name      = module.service_account.name
  bootstrap_project_number  = data.google_project.bootstrap.number
  workload_identity_pool_id = var.workload_identity_pool_id
  tfc_workspace_name        = var.tfc_workspace_name
}
