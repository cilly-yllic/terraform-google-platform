resource "google_firebase_hosting_site" "this" {
  provider = google-beta
  project  = var.project
  site_id  = var.site_id
  app_id   = var.app_id
}
