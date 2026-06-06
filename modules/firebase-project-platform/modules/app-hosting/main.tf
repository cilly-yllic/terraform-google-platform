locals {
  use_custom_sa = var.service_account != ""
}

resource "google_service_account" "app_hosting" {
  count                        = local.use_custom_sa ? 0 : 1
  project                      = var.project
  account_id                   = "firebase-app-hosting-compute"
  display_name                 = "Firebase App Hosting compute service account"
  create_ignore_already_exists = true
}

resource "google_project_iam_member" "app_hosting_runner" {
  count   = local.use_custom_sa ? 0 : 1
  project = var.project
  role    = "roles/firebaseapphosting.computeRunner"
  member  = google_service_account.app_hosting[0].member
}

resource "google_firebase_app_hosting_backend" "this" {
  provider         = google-beta
  project          = var.project
  location         = var.location
  backend_id       = "${var.project}-app-hosting"
  app_id           = var.app_id
  service_account  = local.use_custom_sa ? var.service_account : google_service_account.app_hosting[0].email
  serving_locality = var.serving_locality

  depends_on = [google_project_iam_member.app_hosting_runner]
}
