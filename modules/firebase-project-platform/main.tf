/**
 * Usage:
 *
 * ```tf
 * module "firebase_platform" {
 *   source  = "cilly-yllic/firebase-project-platform/google"
 *   # version = "x.y.z"
 *
 *   project_id = "my-project-id"
 *   region     = "asia-northeast1"
 *
 *   firebase       = true
 *   hosting        = true
 *   firestore      = { location = "asia-northeast1" }
 *   secret_manager = true
 *   authentication = true
 *
 *   ci_service_account = true
 *
 *   users = [
 *     { email = "dev-lead@example.com", role = "editor", deploy = true },
 *   ]
 * }
 * ```
 */

# ---------------------------------------------------------------------------
# Locals – derive enable flags and normalised config from variables
#
# Each feature variable accepts: null (disabled), true (defaults), or { … }.
# We normalise to: enable_* bool + *_config object with defaults applied.
# ---------------------------------------------------------------------------

locals {
  # -- enable flags ----------------------------------------------------------
  enable_firebase        = var.firebase != null
  enable_authentication  = var.authentication != null
  enable_firestore       = var.firestore != null
  enable_rtdb            = var.rtdb != null
  enable_storage         = var.storage != null
  enable_hosting         = var.hosting != null
  enable_app_hosting     = var.app_hosting != null
  enable_data_connect    = var.data_connect != null
  enable_fcm             = var.fcm != null
  enable_remote_config   = var.remote_config != null
  enable_app_check       = var.app_check != null
  enable_crashlytics     = var.crashlytics != null
  enable_performance     = var.performance != null
  enable_analytics       = var.analytics != null
  enable_extensions      = var.extensions != null
  enable_secret_manager  = var.secret_manager != null
  enable_cloud_tasks     = var.cloud_tasks != null
  enable_cloud_scheduler = var.cloud_scheduler != null
  enable_pubsub          = var.pubsub != null
  enable_eventarc        = var.eventarc != null
  enable_cloud_run       = var.cloud_run != null
  enable_cloud_functions = var.cloud_functions != null

  # -- normalised configs (true → {}, null → ignored) -----------------------
  authentication_cfg = local.enable_authentication ? (
    var.authentication == true ? {} : var.authentication
  ) : {}

  firestore_cfg = local.enable_firestore ? (
    var.firestore == true ? {} : var.firestore
  ) : {}

  rtdb_cfg = local.enable_rtdb ? (
    var.rtdb == true ? {} : var.rtdb
  ) : {}

  storage_cfg = local.enable_storage ? (
    var.storage == true ? {} : var.storage
  ) : {}

  hosting_cfg = local.enable_hosting ? (
    var.hosting == true ? {} : var.hosting
  ) : {}

  app_hosting_cfg = local.enable_app_hosting ? (
    var.app_hosting == true ? {} : var.app_hosting
  ) : {}

  data_connect_cfg = local.enable_data_connect ? (
    var.data_connect == true ? {} : var.data_connect
  ) : {}

  cloud_tasks_cfg = local.enable_cloud_tasks ? (
    var.cloud_tasks == true ? {} : var.cloud_tasks
  ) : {}

  cloud_scheduler_cfg = local.enable_cloud_scheduler ? (
    var.cloud_scheduler == true ? {} : var.cloud_scheduler
  ) : {}

  eventarc_cfg = local.enable_eventarc ? (
    var.eventarc == true ? {} : var.eventarc
  ) : {}
}

# ---------------------------------------------------------------------------
# Locals – API auto-determination from enable flags
# ---------------------------------------------------------------------------

locals {
  base_apis = [
    "cloudresourcemanager.googleapis.com",
    "serviceusage.googleapis.com",
  ]

  conditional_apis = concat(
    local.enable_firebase ? [
      "firebase.googleapis.com",
    ] : [],
    local.enable_authentication ? [
      "identitytoolkit.googleapis.com",
    ] : [],
    local.enable_firestore ? [
      "firestore.googleapis.com",
      "firebaserules.googleapis.com",
    ] : [],
    local.enable_rtdb ? [
      "firebasedatabase.googleapis.com",
    ] : [],
    local.enable_storage ? [
      "firebasestorage.googleapis.com",
      "storage.googleapis.com",
      "firebaserules.googleapis.com",
    ] : [],
    local.enable_hosting ? [
      "firebasehosting.googleapis.com",
    ] : [],
    local.enable_app_hosting ? [
      "firebaseapphosting.googleapis.com",
      "run.googleapis.com",
      "cloudbuild.googleapis.com",
      "artifactregistry.googleapis.com",
    ] : [],
    local.enable_data_connect ? [
      "firebasedataconnect.googleapis.com",
      "sqladmin.googleapis.com",
    ] : [],
    local.enable_fcm ? [
      "fcm.googleapis.com",
    ] : [],
    local.enable_remote_config ? [
      "firebaseremoteconfig.googleapis.com",
    ] : [],
    local.enable_app_check ? [
      "firebaseappcheck.googleapis.com",
    ] : [],
    local.enable_crashlytics ? [
      "firebasecrashlytics.googleapis.com",
    ] : [],
    local.enable_performance ? [
      "firebaseperformance.googleapis.com",
    ] : [],
    local.enable_analytics ? [
      "analyticsadmin.googleapis.com",
      "firebase.googleapis.com",
    ] : [],
    local.enable_extensions ? [
      "firebaseextensions.googleapis.com",
    ] : [],
    local.enable_secret_manager ? [
      "secretmanager.googleapis.com",
    ] : [],
    local.enable_cloud_tasks ? [
      "cloudtasks.googleapis.com",
    ] : [],
    local.enable_cloud_scheduler ? [
      "cloudscheduler.googleapis.com",
    ] : [],
    local.enable_pubsub ? [
      "pubsub.googleapis.com",
    ] : [],
    local.enable_eventarc ? [
      "eventarc.googleapis.com",
    ] : [],
    local.enable_cloud_run ? [
      "run.googleapis.com",
    ] : [],
    local.enable_cloud_functions ? [
      "cloudfunctions.googleapis.com",
      "cloudbuild.googleapis.com",
      "artifactregistry.googleapis.com",
    ] : [],
    length(var.service_accounts) > 0 || local.enable_ci_sa || local.enable_app_hosting ? [
      "iam.googleapis.com",
    ] : [],
  )

  all_apis = distinct(concat(local.base_apis, local.conditional_apis, var.additional_apis))
}

# ---------------------------------------------------------------------------
# API Enablement
# ---------------------------------------------------------------------------

resource "google_project_service" "this" {
  for_each                   = toset(local.all_apis)
  project                    = var.project_id
  service                    = each.value
  disable_on_destroy         = false
  disable_dependent_services = true
}

# ---------------------------------------------------------------------------
# Billing
# ---------------------------------------------------------------------------

resource "google_billing_project_info" "this" {
  count           = var.billing_account != "" ? 1 : 0
  project         = var.project_id
  billing_account = var.billing_account
}

# ---------------------------------------------------------------------------
# Firebase Project
# ---------------------------------------------------------------------------

module "firebase" {
  count   = local.enable_firebase ? 1 : 0
  source  = "./modules/firebase"
  project = var.project_id

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Authentication / Identity Platform
# ---------------------------------------------------------------------------

module "auth" {
  count   = local.enable_authentication ? 1 : 0
  source  = "./modules/auth"
  project = var.project_id
  blocking_functions = {
    before_create  = try(local.authentication_cfg.blocking_functions.before_create, "")
    before_sign_in = try(local.authentication_cfg.blocking_functions.before_sign_in, "")
  }

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firestore
# ---------------------------------------------------------------------------

module "firestore" {
  count                   = local.enable_firestore ? 1 : 0
  source                  = "./modules/firestore"
  project                 = var.project_id
  location                = try(local.firestore_cfg.location, "") != "" ? local.firestore_cfg.location : var.region
  type                    = try(local.firestore_cfg.type, "FIRESTORE_NATIVE")
  delete_protection_state = try(local.firestore_cfg.delete_protection_state, "DELETE_PROTECTION_DISABLED")
  point_in_time_recovery  = try(local.firestore_cfg.point_in_time_recovery, false)
  databases               = try(local.firestore_cfg.databases, [])

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Realtime Database
# ---------------------------------------------------------------------------

module "rtdb" {
  count    = local.enable_rtdb ? 1 : 0
  source   = "./modules/rtdb"
  project  = var.project_id
  location = try(local.rtdb_cfg.location, "") != "" ? local.rtdb_cfg.location : var.region
  type     = try(local.rtdb_cfg.type, "DEFAULT_DATABASE")

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Cloud Storage for Firebase
# ---------------------------------------------------------------------------

module "storage" {
  count            = local.enable_storage ? 1 : 0
  source           = "./modules/storage"
  project          = var.project_id
  location         = var.region
  buckets          = try(local.storage_cfg.buckets, [])
  firestore_backup = try(local.storage_cfg.firestore_backup, null)

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Hosting
# ---------------------------------------------------------------------------

module "hosting" {
  count   = local.enable_hosting ? 1 : 0
  source  = "./modules/hosting"
  project = var.project_id
  site_id = try(local.hosting_cfg.site_id, "")

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase App Hosting
# ---------------------------------------------------------------------------

module "app_hosting" {
  count            = local.enable_app_hosting ? 1 : 0
  source           = "./modules/app-hosting"
  project          = var.project_id
  location         = try(local.app_hosting_cfg.location, "") != "" ? local.app_hosting_cfg.location : var.region
  app_id           = try(local.app_hosting_cfg.app_id, "")
  service_account  = try(local.app_hosting_cfg.service_account, "")
  serving_locality = try(local.app_hosting_cfg.serving_locality, "GLOBAL_ACCESS")

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Data Connect
# ---------------------------------------------------------------------------

module "data_connect" {
  count      = local.enable_data_connect ? 1 : 0
  source     = "./modules/data-connect"
  project    = var.project_id
  location   = try(local.data_connect_cfg.location, "") != "" ? local.data_connect_cfg.location : var.region
  service_id = try(local.data_connect_cfg.service_id, "")
  cloud_sql  = try(local.data_connect_cfg.cloud_sql, null)

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Cloud Messaging (FCM)
# ---------------------------------------------------------------------------

module "fcm" {
  count   = local.enable_fcm ? 1 : 0
  source  = "./modules/fcm"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Remote Config
# ---------------------------------------------------------------------------

module "remote_config" {
  count   = local.enable_remote_config ? 1 : 0
  source  = "./modules/remote-config"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase App Check
# ---------------------------------------------------------------------------

module "app_check" {
  count   = local.enable_app_check ? 1 : 0
  source  = "./modules/app-check"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Crashlytics
# ---------------------------------------------------------------------------

module "crashlytics" {
  count   = local.enable_crashlytics ? 1 : 0
  source  = "./modules/crashlytics"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Performance Monitoring
# ---------------------------------------------------------------------------

module "performance" {
  count   = local.enable_performance ? 1 : 0
  source  = "./modules/performance"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Google Analytics for Firebase
# ---------------------------------------------------------------------------

module "analytics" {
  count   = local.enable_analytics ? 1 : 0
  source  = "./modules/analytics"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Extensions
# ---------------------------------------------------------------------------

module "extensions" {
  count   = local.enable_extensions ? 1 : 0
  source  = "./modules/extensions"
  project = var.project_id

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Secret Manager
# ---------------------------------------------------------------------------

module "secret_manager" {
  count   = local.enable_secret_manager ? 1 : 0
  source  = "./modules/secret-manager"
  project = var.project_id

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Cloud Tasks
# ---------------------------------------------------------------------------

module "cloud_tasks" {
  count    = local.enable_cloud_tasks ? 1 : 0
  source   = "./modules/cloud-tasks"
  project  = var.project_id
  location = try(local.cloud_tasks_cfg.location, "") != "" ? local.cloud_tasks_cfg.location : var.region

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Cloud Scheduler
# ---------------------------------------------------------------------------

module "cloud_scheduler" {
  count    = local.enable_cloud_scheduler ? 1 : 0
  source   = "./modules/cloud-scheduler"
  project  = var.project_id
  location = try(local.cloud_scheduler_cfg.location, "") != "" ? local.cloud_scheduler_cfg.location : var.region

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Pub/Sub
# ---------------------------------------------------------------------------

module "pubsub" {
  count   = local.enable_pubsub ? 1 : 0
  source  = "./modules/pubsub"
  project = var.project_id

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Eventarc
# ---------------------------------------------------------------------------

module "eventarc" {
  count    = local.enable_eventarc ? 1 : 0
  source   = "./modules/eventarc"
  project  = var.project_id
  location = try(local.eventarc_cfg.location, "") != "" ? local.eventarc_cfg.location : var.region

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# CI Service Account – auto-determined roles from enabled features
# ---------------------------------------------------------------------------

locals {
  enable_ci_sa = var.ci_service_account != null

  ci_sa_cfg = local.enable_ci_sa ? (
    var.ci_service_account == true ? {} : var.ci_service_account
  ) : {}

  ci_sa_auto_roles = local.enable_ci_sa ? distinct(concat(
    ["roles/runtimeconfig.admin"],
    local.enable_hosting ? ["roles/firebasehosting.admin"] : [],
    local.enable_cloud_functions ? ["roles/cloudfunctions.admin", "roles/iam.serviceAccountUser", "roles/artifactregistry.admin"] : [],
    local.enable_firestore ? ["roles/datastore.indexAdmin", "roles/firebaserules.admin"] : [],
    local.enable_storage ? ["roles/firebasestorage.viewer", "roles/storage.objectAdmin", "roles/storage.admin"] : [],
    local.enable_cloud_scheduler ? ["roles/cloudscheduler.admin"] : [],
    local.enable_cloud_tasks ? ["roles/cloudtasks.queueAdmin"] : [],
    local.enable_authentication ? ["roles/firebaseauth.admin"] : [],
    local.enable_secret_manager ? ["roles/secretmanager.admin"] : [],
    local.enable_cloud_run ? ["roles/run.admin"] : [],
    try(local.ci_sa_cfg.additional_roles, []),
  )) : []
}

# ---------------------------------------------------------------------------
# IAM (Users, CI SA, Service Accounts)
# ---------------------------------------------------------------------------

module "iam" {
  source           = "./modules/iam"
  project          = var.project_id
  users            = var.users
  service_accounts = var.service_accounts

  ci_service_account = local.enable_ci_sa ? {
    account_id   = try(local.ci_sa_cfg.account_id, "ci-deploy")
    display_name = try(local.ci_sa_cfg.display_name, "CI/CD Deployment")
    roles        = local.ci_sa_auto_roles
  } : null

  depends_on = [google_project_service.this]
}
