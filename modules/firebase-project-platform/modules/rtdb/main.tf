resource "google_firebase_database_instance" "this" {
  provider    = google-beta
  project     = var.project
  region      = var.location
  instance_id = "${var.project}-default-rtdb"
  type        = var.type
}
