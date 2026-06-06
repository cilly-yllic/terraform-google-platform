locals {
  project_roles = toset([
    "roles/resourcemanager.projectIamAdmin",
    "roles/serviceusage.serviceUsageAdmin",
    "roles/iam.serviceAccountAdmin",
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
