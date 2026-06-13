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
  enable_firebase       = var.firebase != null
  enable_authentication = var.authentication != null
  enable_firestore      = var.firestore != null
  enable_rtdb           = var.rtdb != null
  enable_storage        = var.storage != null
  # hosting / app_hosting は list が来る → 空 list or null で disable 判定
  enable_hosting     = var.hosting != null && length(local.hosting_list) > 0
  enable_app_hosting = var.app_hosting != null && length(local.app_hosting_list) > 0
  # web_app は user が明示する or hosting/app_hosting がいる時に auto-enable
  enable_web_app = (
    (var.web_app != null && length(local.web_app_list_explicit) > 0) ||
    local.web_app_auto_default_needed
  )
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

  # hosting / app_hosting / web_app は list 化される (詳細は別 locals block)
  # 既存 cfg 形式の hosting / app_hosting は無くなったが、他の location 自動引き継ぎは
  # for_each 内で each.value を使う形で解決する。

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
# Locals – web_app / hosting / app_hosting 正規化 (list 化、auto-default、
# for_each 用 map 生成)。設計詳細:
#   - web_app は array of {name, display_name?} で来る。null/空なら、hosting や
#     app_hosting がいる場合に限り `default` という名前で 1 件 auto-create する。
#   - hosting は array of {site_id, web_app?}。for_each キーは site_id。
#   - app_hosting は array of {backend_id, location?, web_app?, app_id?,
#     service_account?, serving_locality?}。for_each キーは backend_id。
#   - web_app への参照 (h.web_app / a.web_app) は web_app が 1 件しかない時のみ
#     省略可。複数あって省略すると precondition で error。
#   - app_hosting の app_id (raw 外部 pin) と web_app 参照は排他。両方書くと error。
# ---------------------------------------------------------------------------

locals {
  # 入力を list に正規化 (null → 空 list)
  web_app_list_explicit = var.web_app == null ? [] : [
    for w in var.web_app : {
      name         = w.name
      display_name = try(w.display_name, "")
    }
  ]

  hosting_list = var.hosting == null ? [] : [
    for h in var.hosting : {
      site_id = h.site_id
      web_app = try(h.web_app, "")
    }
  ]

  app_hosting_list = var.app_hosting == null ? [] : [
    for a in var.app_hosting : {
      backend_id       = a.backend_id
      location         = try(a.location, "") != "" ? a.location : var.region
      web_app          = try(a.web_app, "")
      app_id           = try(a.app_id, "")
      service_account  = try(a.service_account, "")
      serving_locality = try(a.serving_locality, "GLOBAL_ACCESS")
    }
  ]

  # web_app が空 & hosting/app_hosting が外部 pin で完結していない場合は default を auto-create
  hosting_needs_web_app = length([
    for h in local.hosting_list : h if true
  ]) > 0
  app_hosting_needs_web_app = length([
    for a in local.app_hosting_list : a if a.app_id == "" # 外部 pin でない backend
  ]) > 0
  web_app_auto_default_needed = (
    length(local.web_app_list_explicit) == 0 &&
    (local.hosting_needs_web_app || local.app_hosting_needs_web_app)
  )

  web_app_list = local.web_app_auto_default_needed ? [
    { name = "default", display_name = "" }
  ] : local.web_app_list_explicit

  # for_each 用の map (key = name / site_id / backend_id)
  web_app_map     = { for w in local.web_app_list : w.name => w }
  hosting_map     = { for h in local.hosting_list : h.site_id => h }
  app_hosting_map = { for a in local.app_hosting_list : a.backend_id => a }

  # default web_app key の選定 (=「省略時の単一解決先」)。web_app_list が 1 件のときのみ意味を持つ。
  web_app_default_key = length(local.web_app_list) == 1 ? local.web_app_list[0].name : ""

  # app_hosting で default SA を必要とする backend が 1 つでもあれば共有 SA を作成する
  app_hosting_default_sa_needed = length([
    for a in local.app_hosting_list : a if a.service_account == ""
  ]) > 0
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
    # web_app だけ enable しても firebase API は必須
    local.enable_web_app ? [
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
# Firebase Web App (registration)
#
# google_firebase_web_app は app_id (`1:XXX:web:abc`) を発行する登録 resource。
# Hosting site / App Hosting backend がリンクする先になる。複数定義可。
# ---------------------------------------------------------------------------

module "web_app" {
  for_each     = local.web_app_map
  source       = "./modules/web-app"
  project      = var.project_id
  name         = each.value.name
  display_name = each.value.display_name

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Hosting (multiple sites)
#
# 各 site は site_id (= URL subdomain) で identify。web_app への参照は
# - web_app field 指定があればそれを採用
# - 省略の場合、web_app が 1 件しかなければそれを採用 (web_app_default_key)
# - web_app が複数で省略は precondition で error
# ---------------------------------------------------------------------------

# hosting の web_app 参照を plan-time validate (module block では lifecycle 使え
# ないので terraform_data で代用)。失敗時の error は親 module 側に出る。
resource "terraform_data" "validate_hosting_web_app_refs" {
  for_each = local.hosting_map
  input    = each.key

  lifecycle {
    precondition {
      condition     = each.value.web_app != "" ? contains(keys(local.web_app_map), each.value.web_app) : length(local.web_app_map) == 1
      error_message = "hosting[site_id=${each.key}]: web_app reference '${each.value.web_app}' not found, or web_app omitted while multiple web_app entries exist (ambiguous)."
    }
  }
}

module "hosting" {
  for_each = local.hosting_map
  source   = "./modules/hosting"
  project  = var.project_id
  site_id  = each.value.site_id
  app_id = module.web_app[
    each.value.web_app != "" ? each.value.web_app : local.web_app_default_key
  ].app_id

  depends_on = [
    google_project_service.this,
    module.firebase,
    module.web_app,
    terraform_data.validate_hosting_web_app_refs,
  ]
}

# ---------------------------------------------------------------------------
# Firebase App Hosting (multiple backends)
#
# default SA (firebase-app-hosting-compute) は backend 1 つでも default SA 利用が
# あれば project 単位で 1 個作成して共有する。custom SA を全 backend に指定して
# いる場合は default SA は作らない。
# ---------------------------------------------------------------------------

resource "google_service_account" "app_hosting_default" {
  count                        = local.app_hosting_default_sa_needed ? 1 : 0
  project                      = var.project_id
  account_id                   = "firebase-app-hosting-compute"
  display_name                 = "Firebase App Hosting compute service account"
  create_ignore_already_exists = true

  depends_on = [google_project_service.this]
}

resource "google_project_iam_member" "app_hosting_runner" {
  count   = local.app_hosting_default_sa_needed ? 1 : 0
  project = var.project_id
  role    = "roles/firebaseapphosting.computeRunner"
  member  = google_service_account.app_hosting_default[0].member
}

# app_hosting の参照整合性を plan-time validate (module block では lifecycle が
# 使えないので terraform_data で代用)。排他 check + web_app 参照解決可能性 check。
resource "terraform_data" "validate_app_hosting_refs" {
  for_each = local.app_hosting_map
  input    = each.key

  lifecycle {
    # app_id (外部 pin) と web_app (参照) は同時指定不可
    precondition {
      condition     = !(each.value.app_id != "" && each.value.web_app != "")
      error_message = "app_hosting[backend_id=${each.key}]: cannot specify both 'app_id' (external pin) and 'web_app' (reference). Use one."
    }
    # 外部 pin でなければ web_app の参照解決可能性 check
    precondition {
      condition = each.value.app_id != "" ? true : (
        each.value.web_app != "" ? contains(keys(local.web_app_map), each.value.web_app) : length(local.web_app_map) == 1
      )
      error_message = "app_hosting[backend_id=${each.key}]: web_app reference '${each.value.web_app}' not found, or web_app omitted while multiple web_app entries exist (ambiguous)."
    }
  }
}

module "app_hosting" {
  for_each   = local.app_hosting_map
  source     = "./modules/app-hosting"
  project    = var.project_id
  backend_id = each.value.backend_id
  location   = each.value.location
  app_id = each.value.app_id != "" ? each.value.app_id : module.web_app[
    each.value.web_app != "" ? each.value.web_app : local.web_app_default_key
  ].app_id
  service_account  = each.value.service_account != "" ? each.value.service_account : google_service_account.app_hosting_default[0].email
  serving_locality = each.value.serving_locality

  depends_on = [
    google_project_service.this,
    module.firebase,
    module.web_app,
    google_project_iam_member.app_hosting_runner,
    terraform_data.validate_app_hosting_refs,
  ]
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
