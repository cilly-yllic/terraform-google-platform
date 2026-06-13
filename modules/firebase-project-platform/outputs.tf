# ---------------------------------------------------------------------------
# Project
# ---------------------------------------------------------------------------

output "project_id" {
  description = "GCP project ID."
  value       = var.project_id
}

output "enabled_apis" {
  description = "List of enabled GCP APIs."
  value       = [for k, v in google_project_service.this : v.service]
}

# ---------------------------------------------------------------------------
# Firebase
# ---------------------------------------------------------------------------

output "firebase_project_id" {
  description = "Firebase project ID."
  value       = local.enable_firebase ? module.firebase[0].project_id : null
}

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

output "auth_config_name" {
  description = "Identity Platform config resource name."
  value       = local.enable_authentication ? module.auth[0].name : null
}

# ---------------------------------------------------------------------------
# Firestore
# ---------------------------------------------------------------------------

output "firestore_default_database" {
  description = "Default Firestore database resource name."
  value       = local.enable_firestore ? module.firestore[0].default_database_name : null
}

output "firestore_default_location" {
  description = "Default Firestore database location."
  value       = local.enable_firestore ? module.firestore[0].default_database_location : null
}

output "firestore_additional_databases" {
  description = "Additional Firestore database names."
  value       = local.enable_firestore ? module.firestore[0].additional_databases : {}
}

# ---------------------------------------------------------------------------
# Realtime Database
# ---------------------------------------------------------------------------

output "rtdb_name" {
  description = "Realtime Database instance resource name."
  value       = local.enable_rtdb ? module.rtdb[0].name : null
}

output "rtdb_database_url" {
  description = "Realtime Database URL."
  value       = local.enable_rtdb ? module.rtdb[0].database_url : null
}

# ---------------------------------------------------------------------------
# Cloud Storage
# ---------------------------------------------------------------------------

output "storage_default_bucket" {
  description = "Firebase default Storage bucket name."
  value       = local.enable_storage ? module.storage[0].default_bucket : null
}

output "storage_additional_buckets" {
  description = "Additional bucket names (key = input name, value = resolved GCS name)."
  value       = local.enable_storage ? module.storage[0].additional_buckets : {}
}

# ---------------------------------------------------------------------------
# Web App (multiple)
# ---------------------------------------------------------------------------

output "web_apps" {
  description = "Map of Firebase Web Apps, keyed by name. Each value contains app_id and display_name."
  value = {
    for name, mod in module.web_app : name => {
      app_id       = mod.app_id
      display_name = mod.display_name
    }
  }
}

# ---------------------------------------------------------------------------
# Hosting (multiple sites)
# ---------------------------------------------------------------------------

output "hosting_sites" {
  description = "Map of Firebase Hosting sites, keyed by site_id. Each value contains app_id and default_url."
  value = {
    for site_id, mod in module.hosting : site_id => {
      app_id      = mod.app_id
      default_url = mod.default_url
    }
  }
}

# ---------------------------------------------------------------------------
# App Hosting (multiple backends)
# ---------------------------------------------------------------------------

output "app_hosting_backends" {
  description = "Map of App Hosting backends, keyed by backend_id. Each value contains resource_name and uri."
  value = {
    for backend_id, mod in module.app_hosting : backend_id => {
      resource_name = mod.resource_name
      uri           = mod.uri
    }
  }
}

# ---------------------------------------------------------------------------
# Data Connect
# ---------------------------------------------------------------------------

output "data_connect_name" {
  description = "Data Connect service resource name."
  value       = local.enable_data_connect ? module.data_connect[0].name : null
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

output "user_members" {
  description = "IAM members assigned to users."
  value       = module.iam.user_members
}

output "user_roles" {
  description = "IAM roles assigned to users."
  value       = module.iam.user_roles
}

output "ci_service_account_email" {
  description = "CI service account email."
  value       = module.iam.ci_service_account_email
}

output "ci_service_account_roles" {
  description = "IAM roles auto-assigned to the CI service account."
  value       = module.iam.ci_service_account_roles
}

output "service_account_emails" {
  description = "Created service account emails."
  value       = module.iam.service_account_emails
}

output "service_account_roles" {
  description = "IAM roles assigned to each service account."
  value       = module.iam.service_account_roles
}
