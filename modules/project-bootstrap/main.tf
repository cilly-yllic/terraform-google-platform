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

# ---------------------------------------------------------------------------
# ターゲットプロジェクトの最小 API 有効化
#
# SA をターゲット内に作る (modules/service-account) には iam.googleapis.com が
# 必須。serviceusage / cloudresourcemanager は新規 project でも既定で有効な
# ことが多いが、明示的に有効化して以降の API 操作の前提を固める。
# firebase 等その他の API は後段 (firebase-project-platform) で有効化するので
# ここでは「SA を作るための最小限」に留める。
# 実行者は project-factory SA (org/folder 権限) なので、作成直後の project に
# 対して API 有効化できる (要 serviceusage.serviceUsageAdmin 相当 / 通常は
# project 作成者に付く owner で充足)。
# ---------------------------------------------------------------------------

resource "google_project_service" "bootstrap" {
  for_each = toset([
    "iam.googleapis.com",
    "serviceusage.googleapis.com",
    "cloudresourcemanager.googleapis.com",
  ])
  project                    = module.project.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = false
}

module "service_account" {
  source = "./modules/service-account"

  # SA はターゲットプロジェクト内に作る (infra への SA 集中を回避)。
  project_id         = module.project.project_id
  service_account_id = var.terraform_service_account_id

  # SA 作成は iam API 有効化が前提
  depends_on = [google_project_service.bootstrap]
}

module "iam" {
  source = "./modules/iam"

  project_id                = module.project.project_id
  service_account_email     = module.service_account.email
  service_account_name      = module.service_account.name
  bootstrap_project_number  = var.bootstrap_project_number
  workload_identity_pool_id = var.workload_identity_pool_id
  tfc_workspace_name        = var.tfc_workspace_name
}
