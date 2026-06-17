locals {
  # per-env terraform SA はターゲットプロジェクト専用 (1 project = 1 service-env)
  # なので owner で閉じる。firebase-project-platform モジュールが作る
  # google_firebase_project / Firestore / Storage / Hosting 等を作成するには
  # firebase.admin 等が必要で、個別列挙だと機能追加のたびに権限漏れを起こす。
  # プロジェクト単位で隔離されている前提なので owner が素直 (旧:
  # projectIamAdmin / serviceUsageAdmin / serviceAccountAdmin の 3 ロールは
  # owner に内包される)。
  project_roles = toset([
    "roles/owner",
  ])

  wif_principal = "principalSet://iam.googleapis.com/projects/${var.bootstrap_project_number}/locations/global/workloadIdentityPools/${var.workload_identity_pool_id}/attribute.terraform_workspace/${var.tfc_workspace_name}"
}

resource "google_project_iam_member" "terraform_sa" {
  for_each = local.project_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${var.service_account_email}"
}

resource "google_service_account_iam_member" "workload_identity_user" {
  service_account_id = var.service_account_name
  role               = "roles/iam.workloadIdentityUser"
  member             = local.wif_principal
}
