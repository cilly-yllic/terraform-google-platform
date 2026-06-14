# ---------------------------------------------------------------------------
# Project
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP / Firebase project ID."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be 6-30 lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "Default GCP region for resources."
  type        = string
  default     = "asia-northeast1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]+$", var.region))
    error_message = "region must be a valid GCP region identifier (e.g. asia-northeast1, us-central1)."
  }
}

variable "billing_account" {
  description = "Billing account ID to associate with the project (format: XXXXXX-XXXXXX-XXXXXX). If empty, billing is not configured."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Feature configuration
#
# Each feature variable accepts one of:
#   null  → disabled (no resources created)
#   true  → enabled with default settings
#   { … } → enabled with custom settings (unspecified fields use defaults)
# ---------------------------------------------------------------------------

# -- Firebase core -----------------------------------------------------------

variable "firebase" {
  description = "Firebase Project. null to disable, true for defaults."
  type        = any
  default     = true
}

variable "authentication" {
  description = <<-EOT
    Firebase Authentication / Identity Platform.
    null to disable, true for defaults, or object:
      blocking_functions.before_create  = Cloud Function URI (default: "")
      blocking_functions.before_sign_in = Cloud Function URI (default: "")
  EOT
  type        = any
  default     = null
}

variable "firestore" {
  description = <<-EOT
    Cloud Firestore databases (1 project に複数 DB)。
    null or omitted で disable。

    List of objects:
      database_id              = 必須。"(default)" を含めるかは利用者判断。
                                 SDK の default 動作を期待するなら含める。
      location                 = optional (省略時 var.region)
      type                     = optional ("FIRESTORE_NATIVE" | "DATASTORE_MODE", default "FIRESTORE_NATIVE")
      delete_protection_state  = optional ("DELETE_PROTECTION_DISABLED" | "_ENABLED", default disabled)
      point_in_time_recovery   = optional (bool, default false)

    初期 rules (deny-all) は firestore が 1 件以上あるとき project-level で
    自動適用される。
  EOT
  type        = any
  default     = null
}

variable "rtdb" {
  description = <<-EOT
    Firebase Realtime Database.
    null to disable, true for defaults, or object:
      location = RTDB location (default: var.region)
      type     = DEFAULT_DATABASE | USER_DATABASE (default: "DEFAULT_DATABASE")
  EOT
  type        = any
  default     = null
}

variable "storage" {
  description = <<-EOT
    Cloud Storage for Firebase.
    null to disable, true for defaults (default bucket only), or object:
      buckets = list of additional buckets. Each bucket:
        name          = bucket name (verbatim; globally unique なので衝突注意)
        auto_prefix   = true で `{project_id}-{name}` に組み立てる (default: false)
        location      = bucket location (default: var.region)
        storage_class = storage class (default: "REGIONAL")
        iams          = list of IAM bindings (optional). Each:
          role    = IAM role
          members = list of members
      firestore_backup = Firestore backup bucket config (optional):
        bucket_name     = bucket 名 (verbatim、auto_prefix=true で `{project_id}-` 付与)
        auto_prefix     = true で `{project_id}-{bucket_name}` に組み立てる (default: false)
        export_platform = "cloud_functions" | "cloud_run" (default: "cloud_functions")
    Default bucket is always created when storage is enabled.
  EOT
  type        = any
  default     = null
}

variable "apps" {
  description = <<-EOT
    Firebase Apps (web / iOS / Android registration)。app_id 発行用。
    null or omitted で disable。hosting / app_hosting が指定されていて apps が
    空の場合は自動で 1 件 (name="default", type="web") を auto-create する。

    List of objects (type discriminated):
      name         = 内部参照用 ID (hosting / app_hosting から `app: <name>` で指す)。
                     ※ type 跨いで unique。rename = destroy-recreate になるので
                     immutable 扱い推奨。
      type         = "web" | "ios" | "android"
      display_name = Firebase Console での表示名 (optional, 省略時は name を流用)

      # type=web 専用
      (追加 field なし)

      # type=ios 専用
      bundle_id    = iOS Bundle ID (必須)
      app_store_id = App Store ID (optional, numeric)
      team_id      = Apple Developer Team ID (optional)

      # type=android 専用
      package_name  = Android package name (必須)
      sha1_hashes   = SHA-1 cert hashes (list of strings, optional)
      sha256_hashes = SHA-256 cert hashes (list of strings, optional)

    hosting / app_hosting から参照できるのは type="web" の entry のみ。
  EOT
  type        = any
  default     = null
}

variable "hosting" {
  description = <<-EOT
    Firebase Hosting sites (複数指定可能)。
    null or omitted で disable。

    List of objects:
      site_id     = Hosting site ID (globally unique, URL の subdomain になる)
                    verbatim で扱う。auto_prefix=true の時のみ `{project_id}-` を付与。
      auto_prefix = true で `{project_id}-{site_id}` に組み立てる (default: false)
      app         = 紐付ける apps[].name (optional, type=web のみ参照可)
                    ・type=web の apps が 1 件しか無い時は省略可 (auto-default)
                    ・複数 / 0 件で省略 / 不在の名前 / 非 web type を参照 = plan-time error
  EOT
  type        = any
  default     = null
}

variable "app_hosting" {
  description = <<-EOT
    Firebase App Hosting backends (複数指定可能)。
    null or omitted で disable。

    List of objects:
      backend_id       = Backend ID (project-unique, Firebase Console title)
                         [a-z][a-z0-9-]{2,30}[a-z0-9]
      location         = Backend location (default: var.region)
      app              = 紐付ける apps[].name (type=web のみ参照可、単数なら省略可)
      app_id           = 外部 Web App ID を pin したい場合のみ指定。app と排他
                         (両方書くと plan-time error)
      service_account  = Service account email (default: 自動で project 共有の SA を作成)
      serving_locality = GLOBAL_ACCESS | REGION_LOCKED (default: "GLOBAL_ACCESS")
  EOT
  type        = any
  default     = null
}

variable "data_connect" {
  description = <<-EOT
    Firebase Data Connect services (1 project に複数 service)。
    null or omitted で disable。

    List of objects:
      service_id  = 必須 (project-unique)
      location    = optional (default: var.region)
      cloud_sql   = 必須 (Cloud SQL backend が必要):
        instance_id         = 必須。複数 service が同 instance_id を指せば
                              自動 dedup して 1 instance に集約 (コスト最適化)
        database            = 必須 (instance 内の logical database 名)
        tier                = optional (default "db-f1-micro"、同 instance_id を
                              共有する entries 間で一致必須)
        database_version    = optional (default "POSTGRES_15"、同様に一致必須)
        deletion_protection = optional (default false、同様に一致必須)
        location            = optional (default はその service の location、
                              同 instance_id 内で一致必須)
  EOT
  type        = any
  default     = null
}

# -- Firebase extensions -----------------------------------------------------

variable "fcm" {
  description = "Firebase Cloud Messaging. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "remote_config" {
  description = "Firebase Remote Config. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "app_check" {
  description = "Firebase App Check. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "crashlytics" {
  description = "Firebase Crashlytics. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "performance" {
  description = "Firebase Performance Monitoring. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "analytics" {
  description = "Google Analytics for Firebase. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "extensions" {
  description = "Firebase Extensions. null to disable, true for defaults."
  type        = any
  default     = null
}

# -- GCP services ------------------------------------------------------------

variable "secret_manager" {
  description = "Secret Manager. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "cloud_tasks" {
  description = <<-EOT
    Cloud Tasks.
    null to disable, true for defaults, or object:
      location = Cloud Tasks location (default: var.region)
  EOT
  type        = any
  default     = null
}

variable "cloud_scheduler" {
  description = <<-EOT
    Cloud Scheduler.
    null to disable, true for defaults, or object:
      location = Cloud Scheduler location (default: var.region)
  EOT
  type        = any
  default     = null
}

variable "pubsub" {
  description = "Pub/Sub. null to disable, true for defaults."
  type        = any
  default     = null
}

variable "eventarc" {
  description = <<-EOT
    Eventarc.
    null to disable, true for defaults, or object:
      location = Eventarc location (default: var.region)
  EOT
  type        = any
  default     = null
}

variable "cloud_run" {
  description = "Cloud Run IAM configuration. null to disable, true to enable."
  type        = any
  default     = null
}

variable "cloud_functions" {
  description = "Cloud Functions IAM configuration. null to disable, true to enable."
  type        = any
  default     = null
}

# ---------------------------------------------------------------------------
# API management
# ---------------------------------------------------------------------------

variable "additional_apis" {
  description = "Additional GCP APIs to enable beyond those auto-determined by feature flags."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for s in var.additional_apis : can(regex("\\.googleapis\\.com$", s))])
    error_message = "Each additional_apis entry must end with '.googleapis.com'."
  }
}

# ---------------------------------------------------------------------------
# IAM – Users
# ---------------------------------------------------------------------------

variable "users" {
  description = <<-EOT
    Project IAM members to grant roles to.
      email  = user email address (required)
      role   = viewer | editor | owner (default: "viewer")
      deploy = grant Cloud Functions / Artifact Registry deploy roles (default: false)
  EOT
  type = list(object({
    email  = string
    role   = optional(string, "viewer")
    deploy = optional(bool, false)
  }))
  default = []

  validation {
    condition     = alltrue([for u in var.users : contains(["viewer", "editor", "owner"], u.role)])
    error_message = "users[*].role must be one of: viewer, editor, owner."
  }
}

# ---------------------------------------------------------------------------
# CI Service Account (auto-determined roles from enabled features)
# ---------------------------------------------------------------------------

variable "ci_service_account" {
  description = <<-EOT
    CI deploy service account. Roles are auto-determined from enabled features.
    null to disable, true for defaults, or object:
      account_id       = SA ID (default: "ci-deploy")
      display_name     = display name (default: "CI/CD Deployment")
      additional_roles = extra roles to grant beyond auto-determined (default: [])
  EOT
  type        = any
  default     = null
}

# ---------------------------------------------------------------------------
# Service Accounts (manual)
# ---------------------------------------------------------------------------

variable "service_accounts" {
  description = <<-EOT
    Additional service accounts to create with explicit role assignment.
      account_id   = SA ID (required)
      display_name = display name (optional)
      type         = "deploy" (required)
      roles        = additional custom IAM roles (optional)
      args         = feature flags for deploy type:
        hosting   = true/false (roles/firebasehosting.admin)
        functions = true/false (roles/cloudfunctions.admin, roles/iam.serviceAccountUser, roles/artifactregistry.admin)
        firestore = true/false (roles/datastore.indexAdmin, roles/firebaserules.admin)
        storage   = true/false (roles/firebasestorage.viewer, roles/storage.objectAdmin, roles/storage.admin)
        scheduler = true/false (roles/cloudscheduler.admin)
        tasks     = true/false (roles/cloudtasks.queueAdmin)
        blocking  = true/false (roles/firebaseauth.admin)
  EOT
  type = list(object({
    account_id   = string
    display_name = optional(string, "")
    type         = string
    roles        = optional(list(string), [])
    args         = optional(any, {})
  }))
  default = []
}
