resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = var.service_account_id
  display_name = "Terraform SA for ${var.service_account_id}"
}
