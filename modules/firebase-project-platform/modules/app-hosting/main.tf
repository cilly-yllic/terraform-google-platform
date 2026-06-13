resource "google_firebase_app_hosting_backend" "this" {
  provider         = google-beta
  project          = var.project
  location         = var.location
  backend_id       = var.backend_id
  app_id           = var.app_id
  service_account  = var.service_account
  serving_locality = var.serving_locality
}
