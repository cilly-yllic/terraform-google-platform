resource "google_firebase_apple_app" "this" {
  provider     = google-beta
  project      = var.project
  bundle_id    = var.bundle_id
  display_name = var.display_name != "" ? var.display_name : var.name
  app_store_id = var.app_store_id != "" ? var.app_store_id : null
  team_id      = var.team_id != "" ? var.team_id : null
}
