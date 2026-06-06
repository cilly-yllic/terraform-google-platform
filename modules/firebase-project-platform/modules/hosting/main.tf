locals {
  site_id = var.site_id != "" ? var.site_id : var.project
}

resource "google_firebase_web_app" "this" {
  provider     = google-beta
  project      = var.project
  display_name = local.site_id
}

resource "google_firebase_hosting_site" "this" {
  provider = google-beta
  project  = var.project
  site_id  = local.site_id
  app_id   = google_firebase_web_app.this.app_id
}
