resource "google_firebase_web_app" "this" {
  provider     = google-beta
  project      = var.project
  display_name = var.display_name != "" ? var.display_name : var.name
}
