resource "google_project" "this" {
  project_id          = var.project_id
  name                = var.project_name
  org_id              = var.folder_id == null ? var.org_id : null
  folder_id           = var.folder_id
  billing_account     = var.billing_account_id
  labels              = var.labels
  auto_create_network = false
  deletion_policy     = var.deletion_policy

  lifecycle {
    precondition {
      condition     = var.org_id != null || var.folder_id != null
      error_message = "At least one of org_id or folder_id must be specified."
    }
  }
}
