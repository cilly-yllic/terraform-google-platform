resource "google_firebase_android_app" "this" {
  provider      = google-beta
  project       = var.project
  package_name  = var.package_name
  display_name  = var.display_name != "" ? var.display_name : var.name
  sha1_hashes   = var.sha1_hashes
  sha256_hashes = var.sha256_hashes
}
