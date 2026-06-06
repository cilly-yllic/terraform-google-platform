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
# Hosting
# ---------------------------------------------------------------------------

output "hosting_site_id" {
  description = "Firebase Hosting site ID."
  value       = local.enable_hosting ? module.hosting[0].site_id : null
}

output "hosting_app_id" {
  description = "Firebase Web App ID."
  value       = local.enable_hosting ? module.hosting[0].app_id : null
}

output "hosting_default_url" {
  description = "Firebase Hosting default URL."
  value       = local.enable_hosting ? module.hosting[0].default_url : null
}

# ---------------------------------------------------------------------------
# App Hosting
# ---------------------------------------------------------------------------

output "app_hosting_name" {
  description = "App Hosting backend resource name."
  value       = local.enable_app_hosting ? module.app_hosting[0].name : null
}

output "app_hosting_uri" {
  description = "App Hosting backend URI."
  value       = local.enable_app_hosting ? module.app_hosting[0].uri : null
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
