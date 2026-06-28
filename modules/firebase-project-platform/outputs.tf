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

output "firestore_databases" {
  description = "Map of Firestore databases, keyed by database_id. Each value contains name, location, type."
  value       = local.enable_firestore ? module.firestore[0].databases : {}
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
# Apps (web / iOS / Android, type 別 map で出力)
# ---------------------------------------------------------------------------

output "web_apps" {
  description = "Map of Firebase Web Apps, keyed by apps[].name (type=web). Each value contains app_id and display_name."
  value = {
    for name, mod in module.apps_web : name => {
      app_id       = mod.app_id
      display_name = mod.display_name
    }
  }
}

output "ios_apps" {
  description = "Map of Firebase Apple Apps, keyed by apps[].name (type=ios). Each value contains app_id, bundle_id, display_name."
  value = {
    for name, mod in module.apps_ios : name => {
      app_id       = mod.app_id
      bundle_id    = mod.bundle_id
      display_name = mod.display_name
    }
  }
}

output "android_apps" {
  description = "Map of Firebase Android Apps, keyed by apps[].name (type=android). Each value contains app_id, package_name, display_name."
  value = {
    for name, mod in module.apps_android : name => {
      app_id       = mod.app_id
      package_name = mod.package_name
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
      # 各 custom domain の required_dns_updates (別 DNS レイヤで登録する用)。
      custom_domains = mod.custom_domains
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
      # app-hosting submodule の output 名は `name` (resource_name ではない)。
      # 公開 output のキーは resource_name のまま維持する。
      resource_name = mod.name
      uri           = mod.uri
      # 各 custom domain の required_dns_updates (別 DNS レイヤで登録する用)。
      custom_domains = mod.custom_domains
    }
  }
}

# ---------------------------------------------------------------------------
# Data Connect
# ---------------------------------------------------------------------------

output "data_connect_services" {
  description = "Map of Data Connect services, keyed by service_id."
  value       = local.enable_data_connect ? module.data_connect[0].services : {}
}

output "data_connect_cloud_sql_instances" {
  description = "Map of Cloud SQL instances created by Data Connect, keyed by instance_id (deduplicated when multiple services share the same instance)."
  value       = local.enable_data_connect ? module.data_connect[0].cloud_sql_instances : {}
}

output "data_connect_cloud_sql_databases" {
  description = "Map of Cloud SQL databases, keyed by '{instance_id}/{database}'."
  value       = local.enable_data_connect ? module.data_connect[0].cloud_sql_databases : {}
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

output "ci_service_account_wif_members" {
  description = "WIF principalSet members bound to the CI service account (empty list when wif is not configured)."
  value       = module.iam.ci_service_account_wif_members
}

output "service_account_emails" {
  description = "Created service account emails."
  value       = module.iam.service_account_emails
}

output "service_account_roles" {
  description = "IAM roles assigned to each service account."
  value       = module.iam.service_account_roles
}

output "service_account_wif_members" {
  description = "WIF principalSet members bound to manual service accounts (empty when none configure wif)."
  value       = module.iam.service_account_wif_members
}
