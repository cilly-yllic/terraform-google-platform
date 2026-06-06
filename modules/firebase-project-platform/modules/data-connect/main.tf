locals {
  service_id  = var.service_id != "" ? var.service_id : "${var.project}-dataconnect"
  instance_id = var.cloud_sql != null ? (var.cloud_sql.instance_id != "" ? var.cloud_sql.instance_id : "${var.project}-fdc") : ""
  database    = var.cloud_sql != null ? (var.cloud_sql.database != "" ? var.cloud_sql.database : var.project) : ""
}

# ---------------------------------------------------------------------------
# Data Connect Service
# ---------------------------------------------------------------------------

resource "google_firebase_data_connect_service" "this" {
  provider   = google-beta
  project    = var.project
  location   = var.location
  service_id = local.service_id
}

# ---------------------------------------------------------------------------
# Cloud SQL Instance (optional)
# ---------------------------------------------------------------------------

resource "google_sql_database_instance" "this" {
  count               = var.cloud_sql != null ? 1 : 0
  project             = var.project
  name                = local.instance_id
  region              = var.location
  database_version    = var.cloud_sql.database_version
  deletion_protection = var.cloud_sql.deletion_protection

  settings {
    tier              = var.cloud_sql.tier
    edition           = "ENTERPRISE"
    availability_type = "ZONAL"

    backup_configuration {
      enabled = true
    }

    ip_configuration {
      ipv4_enabled = true
    }
  }
}

resource "google_sql_database" "this" {
  count    = var.cloud_sql != null ? 1 : 0
  project  = var.project
  instance = google_sql_database_instance.this[0].name
  name     = local.database
}
