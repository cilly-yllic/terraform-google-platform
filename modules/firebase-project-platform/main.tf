/**
 * Usage:
 *
 * ```tf
 * module "firebase_platform" {
 *   source  = "cilly-yllic/platform/google//modules/firebase-project-platform"
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
  enable_firestore      = var.firestore != null && length(local.firestore_list) > 0
  enable_rtdb           = var.rtdb != null
  enable_storage        = var.storage != null
  # hosting / app_hosting は list が来る → 空 list or null で disable 判定
  enable_hosting     = var.hosting != null && length(local.hosting_list) > 0
  enable_app_hosting = var.app_hosting != null && length(local.app_hosting_list) > 0
  # apps は user が明示する or hosting/app_hosting がいる時に auto-enable
  enable_apps = (
    (var.apps != null && length(local.apps_list_explicit) > 0) ||
    local.apps_auto_default_needed
  )
  enable_data_connect    = var.data_connect != null && length(local.data_connect_list) > 0
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

  # -- normalised configs (true → null, object → そのまま, null → ignored) ----
  # 前提: 各変数は type=any で「null=無効 / true=デフォルトで有効 / object=詳細指定」
  # の 3 値を取る。true を空オブジェクト {} に正規化したかったが、Terraform の
  # 条件式 `cond ? a : b` は a / b の型が一致しないと
  #   "Inconsistent conditional result types"
  # で失敗する。{} (空 object) は bool の true とも、属性を持つ object とも
  # 型が一致しないため、true 指定時・object 指定時の双方でエラーになっていた。
  # null は任意の型に変換可能で必ず型一致するため、空デフォルトは null で表す。
  # 下流の参照はすべて `try(local.*_cfg.attr, default)` なので null でも安全
  # (null の属性アクセスは try が握りつぶしデフォルトに落ちる)。
  authentication_cfg = local.enable_authentication ? (
    var.authentication == true ? null : var.authentication
  ) : null

  # firestore / data_connect は list 化される (詳細は別 locals block)

  rtdb_cfg = local.enable_rtdb ? (
    var.rtdb == true ? null : var.rtdb
  ) : null

  storage_cfg = local.enable_storage ? (
    var.storage == true ? null : var.storage
  ) : null

  # hosting / app_hosting / web_app は list 化される (詳細は別 locals block)
  # 既存 cfg 形式の hosting / app_hosting は無くなったが、他の location 自動引き継ぎは
  # for_each 内で each.value を使う形で解決する。

  # (data_connect_cfg は廃止、list 形式に正規化)

  cloud_tasks_cfg = local.enable_cloud_tasks ? (
    var.cloud_tasks == true ? null : var.cloud_tasks
  ) : null

  cloud_scheduler_cfg = local.enable_cloud_scheduler ? (
    var.cloud_scheduler == true ? null : var.cloud_scheduler
  ) : null

  eventarc_cfg = local.enable_eventarc ? (
    var.eventarc == true ? null : var.eventarc
  ) : null
}

# ---------------------------------------------------------------------------
# Locals – apps / hosting / app_hosting 正規化 (list 化、auto-default、
# for_each 用 map 生成)。設計詳細:
#   - apps は array of {name, type, …type-specific…} で来る。
#     - type: "web" | "ios" | "android" (lowercase)
#     - type=web      : 追加 field なし (display_name optional)
#     - type=ios      : bundle_id 必須、app_store_id / team_id optional
#     - type=android  : package_name 必須、sha1_hashes / sha256_hashes optional
#     - name は type 跨いで unique でなければならない (for_each キーになる)
#     - null/空なら、hosting や app_hosting がいる場合に限り
#       `default` という名前で web type を 1 件 auto-create する。
#   - hosting は array of {site_id, app?}。for_each キーは site_id。
#     - app は apps[].name を参照 (type=web の entry のみ参照可)。
#   - app_hosting は array of {backend_id, location?, app?, app_id?,
#     service_account?, serving_locality?}。for_each キーは backend_id。
#     - app は apps[].name (type=web のみ)、app_id は外部 pin の場合のみ。
#   - app 参照 (h.app / a.app) は web type entry が 1 件しかない時のみ省略可。
#     複数あって省略 / 存在しない名前 / type=web 以外を参照 = precondition error。
#   - app_hosting の app_id (raw 外部 pin) と app 参照は排他。両方書くと error。
# ---------------------------------------------------------------------------

locals {
  # firestore を list に正規化 (null → 空 list)
  firestore_list = var.firestore == null ? [] : [
    for db in var.firestore : {
      database_id             = db.database_id
      location                = try(db.location, "")
      type                    = try(db.type, "FIRESTORE_NATIVE")
      delete_protection_state = try(db.delete_protection_state, "DELETE_PROTECTION_DISABLED")
      point_in_time_recovery  = try(db.point_in_time_recovery, false)
    }
  ]

  # data_connect を list に正規化 (null → 空 list)
  data_connect_list = var.data_connect == null ? [] : [
    for s in var.data_connect : {
      service_id = s.service_id
      location   = try(s.location, "")
      cloud_sql = {
        instance_id         = s.cloud_sql.instance_id
        database            = s.cloud_sql.database
        tier                = try(s.cloud_sql.tier, "db-f1-micro")
        database_version    = try(s.cloud_sql.database_version, "POSTGRES_15")
        deletion_protection = try(s.cloud_sql.deletion_protection, false)
        location            = try(s.cloud_sql.location, "")
      }
    }
  ]

  # 入力 apps を list に正規化 (null → 空 list)。type 別 field を全部読み出して
  # 1 つの shape にする (使わない field は空文字 / 空 list として保持)。
  apps_list_explicit = var.apps == null ? [] : [
    for a in var.apps : {
      name          = a.name
      type          = a.type
      display_name  = try(a.display_name, "")
      bundle_id     = try(a.bundle_id, "")     # ios のみ
      app_store_id  = try(a.app_store_id, "")  # ios optional
      team_id       = try(a.team_id, "")       # ios optional
      package_name  = try(a.package_name, "")  # android のみ
      sha1_hashes   = try(a.sha1_hashes, [])   # android optional
      sha256_hashes = try(a.sha256_hashes, []) # android optional
    }
  ]

  # site_id は globally unique。auto_prefix=true の時のみ `{project_id}-` で包む。
  # for_each キーは 入力 site_id を維持 (state stability 用、resolved は実際の
  # google_firebase_hosting_site.site_id に渡す)。
  hosting_list = var.hosting == null ? [] : [
    for h in var.hosting : {
      site_id          = h.site_id
      auto_prefix      = try(h.auto_prefix, false)
      resolved_site_id = try(h.auto_prefix, false) ? "${var.project_id}-${h.site_id}" : h.site_id
      app              = try(h.app, "")
    }
  ]

  app_hosting_list = var.app_hosting == null ? [] : [
    for a in var.app_hosting : {
      backend_id       = a.backend_id
      location         = try(a.location, "") != "" ? a.location : var.region
      app              = try(a.app, "")
      app_id           = try(a.app_id, "")
      service_account  = try(a.service_account, "")
      serving_locality = try(a.serving_locality, "GLOBAL_ACCESS")
    }
  ]

  # apps が空 & hosting/app_hosting が外部 pin で完結していない場合は
  # `default` 名で type=web を 1 件 auto-create する (Web App は hosting /
  # app_hosting のリンク用に必要、iOS / Android はそうではないので auto-create
  # 対象外)。
  hosting_needs_web_app = length(local.hosting_list) > 0
  app_hosting_needs_web_app = length([
    for a in local.app_hosting_list : a if a.app_id == "" # 外部 pin でない backend
  ]) > 0
  apps_auto_default_needed = (
    length(local.apps_list_explicit) == 0 &&
    (local.hosting_needs_web_app || local.app_hosting_needs_web_app)
  )

  apps_list = local.apps_auto_default_needed ? [
    {
      name          = "default"
      type          = "web"
      display_name  = ""
      bundle_id     = ""
      app_store_id  = ""
      team_id       = ""
      package_name  = ""
      sha1_hashes   = []
      sha256_hashes = []
    }
  ] : local.apps_list_explicit

  # type 別の map に分割 (for_each キー = name)。同 type 内で name 重複は
  # for_each 自体が duplicate key で error にしてくれる。
  apps_web_map     = { for a in local.apps_list : a.name => a if a.type == "web" }
  apps_ios_map     = { for a in local.apps_list : a.name => a if a.type == "ios" }
  apps_android_map = { for a in local.apps_list : a.name => a if a.type == "android" }

  # 全 type を通した name uniqueness check 用の map (重複あると key 衝突で error)。
  apps_all_map = { for a in local.apps_list : a.name => a }

  hosting_map     = { for h in local.hosting_list : h.site_id => h }
  app_hosting_map = { for a in local.app_hosting_list : a.backend_id => a }

  # default app key の選定 (=「app 参照省略時の単一解決先」)。
  # type=web の entry が 1 件のときのみ意味を持つ (それ以外は "" にして
  # precondition で必須化)。
  apps_web_default_key = length(local.apps_web_map) == 1 ? keys(local.apps_web_map)[0] : ""

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
    # apps だけ enable しても firebase API は必須
    local.enable_apps ? [
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
      # CLI (`firebase deploy --only apphosting`, local source) は Cloud Build で
      # ビルドし Cloud Run + Artifact Registry にデプロイするため必須。
      "run.googleapis.com",
      "cloudbuild.googleapis.com",
      "artifactregistry.googleapis.com",
    ] : [],
    local.enable_data_connect ? [
      "firebasedataconnect.googleapis.com",
      "sqladmin.googleapis.com",
      # Data Connect (Cloud SQL) deploy 時、firebase CLI が課金有効性を Cloud Billing
      # API (billingInfo) で確認するため必須。未有効だと
      # "Cloud Billing API has not been used in project ..." 403 で落ちる。
      # firestore/storage は billing チェック不要なのでこの API も不要だった。
      "cloudbilling.googleapis.com",
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
      # Gen2 Functions は Cloud Run / Eventarc / Pub/Sub を内部利用するため、
      # これらの API と service-agent binding が deploy に必須。
      "run.googleapis.com",
      "eventarc.googleapis.com",
      "pubsub.googleapis.com",
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
# API 有効化の伝播待ち
#
# google_project_service は有効化リクエストが受理された時点で完了扱いになるが、
# firebase.googleapis.com 等は実際に使えるようになるまで GCP 側で数分の伝播遅延が
# ある。直後に Firebase Management API を叩く google_firebase_project が走ると
# 403 SERVICE_DISABLED ("...has not been used... or it is disabled") になる race を
# 起こすため、ここで待ってから Firebase 系リソースを作る。
#
# 注: Firebase Management API を直接ポーリングして「浸透完了」を実判定する案も
# 検討したが、TFC dynamic credentials (WIF→run SA impersonation) 環境では
# data.google_client_config が bearer token を取得する際に
# iam.serviceAccounts.getAccessToken 403 になり成立しなかった。auth 依存ゼロで
# 確実な固定待ちに倒す。待ち時間は race を避けつつ過剰待ちしないよう
# var.firebase_api_propagation_wait で可変 (既定 120s)。
#
# create_duration は triggers が変わった時だけ作り直されるので、API セットが
# 不変の再 apply では待ちは発生しない (毎 apply で待たせない)。
# 関連: modules/firebase/main.tf (google_firebase_project)
# firebase / apps を作らない構成では不要なので count で抑止する。
# ---------------------------------------------------------------------------

resource "time_sleep" "api_propagation" {
  count           = local.enable_firebase || local.enable_apps ? 1 : 0
  create_duration = var.firebase_api_propagation_wait

  # API セットが変わった時だけ待ち直す (毎 apply で待たせない)
  triggers = {
    apis = join(",", local.all_apis)
  }

  depends_on = [google_project_service.this]
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

  # API 伝播待ちを挟む (time_sleep.api_propagation 参照)。大半の Firebase 系
  # サブモジュールは module.firebase に depends_on しているので、ここを待たせれば
  # 連鎖的に伝播 race を防げる。
  depends_on = [google_project_service.this, time_sleep.api_propagation]
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
  count            = local.enable_firestore ? 1 : 0
  source           = "./modules/firestore"
  project          = var.project_id
  default_location = var.region
  databases        = local.firestore_list

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
  default_bucket   = try(local.storage_cfg.default_bucket, false)
  buckets          = try(local.storage_cfg.buckets, [])
  firestore_backup = try(local.storage_cfg.firestore_backup, null)

  depends_on = [google_project_service.this, module.firebase]
}

# ---------------------------------------------------------------------------
# Firebase Apps (registration)
#
# `var.apps` を type 別に分けて、それぞれ対応する submodule で作成する。
#   - type=web     → modules/web-app/     (google_firebase_web_app)
#   - type=ios     → modules/ios-app/     (google_firebase_apple_app)
#   - type=android → modules/android-app/ (google_firebase_android_app)
# どの type も app_id を auto-generate する。hosting / app_hosting がリンクする
# 先になる app_id は web type のものだけ。
#
# type 別 validation (type-specific required field) は各 submodule の variable
# block の validation で plan-time check される (例: ios は bundle_id 必須)。
# ---------------------------------------------------------------------------

module "apps_web" {
  for_each     = local.apps_web_map
  source       = "./modules/web-app"
  project      = var.project_id
  name         = each.value.name
  display_name = each.value.display_name

  # firebase=false で apps だけ作る構成 (module.firebase が count 0) でも
  # API 伝播 race を防ぐため time_sleep を直接待つ。
  depends_on = [google_project_service.this, module.firebase, time_sleep.api_propagation]
}

module "apps_ios" {
  for_each     = local.apps_ios_map
  source       = "./modules/ios-app"
  project      = var.project_id
  name         = each.value.name
  bundle_id    = each.value.bundle_id
  display_name = each.value.display_name
  app_store_id = each.value.app_store_id
  team_id      = each.value.team_id

  depends_on = [google_project_service.this, module.firebase, time_sleep.api_propagation]
}

module "apps_android" {
  for_each      = local.apps_android_map
  source        = "./modules/android-app"
  project       = var.project_id
  name          = each.value.name
  package_name  = each.value.package_name
  display_name  = each.value.display_name
  sha1_hashes   = each.value.sha1_hashes
  sha256_hashes = each.value.sha256_hashes

  depends_on = [google_project_service.this, module.firebase, time_sleep.api_propagation]
}

# apps 全体の name uniqueness を plan-time で validate (type 跨いで重複は許さない)。
resource "terraform_data" "validate_apps_uniqueness" {
  count = length(local.apps_list) > 0 ? 1 : 0
  input = "apps"

  lifecycle {
    precondition {
      condition     = length(local.apps_list) == length(local.apps_all_map)
      error_message = "apps[].name must be unique across all types (web / ios / android)."
    }
    precondition {
      condition = alltrue([
        for a in local.apps_list : contains(["web", "ios", "android"], a.type)
      ])
      error_message = "apps[].type must be one of: web | ios | android."
    }
  }
}

# ---------------------------------------------------------------------------
# Firebase Hosting (multiple sites)
#
# 各 site は site_id (= URL subdomain) で identify。app への参照は:
#   - app field 指定があればそれを採用 (type=web の entry のみ参照可)
#   - 省略の場合、type=web の entry が 1 件しかなければそれを採用 (auto-default)
#   - 0 件 or 複数で省略は precondition で error
#   - 存在しない名前 / type が web 以外を参照も precondition で error
# ---------------------------------------------------------------------------

resource "terraform_data" "validate_hosting_app_refs" {
  for_each = local.hosting_map
  input    = each.key

  lifecycle {
    precondition {
      condition     = each.value.app != "" ? contains(keys(local.apps_web_map), each.value.app) : length(local.apps_web_map) == 1
      error_message = "hosting[site_id=${each.key}]: app reference '${each.value.app}' not found among type=web apps, or app omitted while multiple (or zero) web apps exist (ambiguous)."
    }
  }
}

module "hosting" {
  for_each = local.hosting_map
  source   = "./modules/hosting"
  project  = var.project_id
  # auto_prefix=true の時は `{project_id}-{site_id}` が実際の Hosting site ID。
  site_id = each.value.resolved_site_id
  app_id = module.apps_web[
    each.value.app != "" ? each.value.app : local.apps_web_default_key
  ].app_id

  depends_on = [
    google_project_service.this,
    module.firebase,
    module.apps_web,
    terraform_data.validate_hosting_app_refs,
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

# 共有 compute SA への追加 role 付与 (runtime で他 API を叩く用)。
# 例: backend が Cloud Tasks に enqueue するなら "roles/cloudtasks.enqueuer"。
# 共有 default SA が作られる時のみ有効 (全 backend が custom SA を使う構成では
# toset([]) で no-op になり、google_service_account.app_hosting_default[0] も
# 評価されない)。non-authoritative な iam_member なので既存 binding を壊さない。
resource "google_project_iam_member" "app_hosting_compute_extra" {
  for_each = local.app_hosting_default_sa_needed ? toset(var.app_hosting_compute_sa_roles) : toset([])
  project  = var.project_id
  role     = each.value
  member   = google_service_account.app_hosting_default[0].member
}

# app_hosting の参照整合性を plan-time validate。
#   - app_id (外部 pin) と app (内部参照) は排他
#   - 外部 pin でない時は app refs を解決できる必要あり (type=web のみ)
resource "terraform_data" "validate_app_hosting_refs" {
  for_each = local.app_hosting_map
  input    = each.key

  lifecycle {
    precondition {
      condition     = !(each.value.app_id != "" && each.value.app != "")
      error_message = "app_hosting[backend_id=${each.key}]: cannot specify both 'app_id' (external pin) and 'app' (reference). Use one."
    }
    precondition {
      condition = each.value.app_id != "" ? true : (
        each.value.app != "" ? contains(keys(local.apps_web_map), each.value.app) : length(local.apps_web_map) == 1
      )
      error_message = "app_hosting[backend_id=${each.key}]: app reference '${each.value.app}' not found among type=web apps, or app omitted while multiple (or zero) web apps exist (ambiguous)."
    }
  }
}

# ---------------------------------------------------------------------------
# App Hosting backend (bare)
#
# 運用モデル:
#   - terraform は backend の「箱」と compute SA だけを作る。
#   - 実際のコードのデプロイは firebase CLI (`firebase deploy --only apphosting`,
#     local source) が build / rollout を作って行う (terraform 管理外の別レイヤ →
#     state 汚染なし)。CI SA は ci_sa_auto_roles の firebaseapphosting.admin /
#     iam.serviceAccountUser で rollout 可能 (backend / compute SA は terraform が
#     先に作るので CLI は serviceAccounts.create を必要としない)。
# ---------------------------------------------------------------------------

module "app_hosting" {
  for_each   = local.app_hosting_map
  source     = "./modules/app-hosting"
  project    = var.project_id
  backend_id = each.value.backend_id
  location   = each.value.location
  app_id = each.value.app_id != "" ? each.value.app_id : module.apps_web[
    each.value.app != "" ? each.value.app : local.apps_web_default_key
  ].app_id
  service_account  = each.value.service_account != "" ? each.value.service_account : google_service_account.app_hosting_default[0].email
  serving_locality = each.value.serving_locality

  depends_on = [
    google_project_service.this,
    module.firebase,
    module.apps_web,
    google_project_iam_member.app_hosting_runner,
    terraform_data.validate_app_hosting_refs,
  ]
}

# ---------------------------------------------------------------------------
# Firebase Data Connect
# ---------------------------------------------------------------------------

module "data_connect" {
  count            = local.enable_data_connect ? 1 : 0
  source           = "./modules/data-connect"
  project          = var.project_id
  default_location = var.region
  services         = local.data_connect_list

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

  # true → null 正規化 (理由は上部 *_cfg の locals block コメント参照)。
  # 参照側は try(local.ci_sa_cfg.attr, default) なので null でも安全。
  ci_sa_cfg = local.enable_ci_sa ? (
    var.ci_service_account == true ? null : var.ci_service_account
  ) : null

  ci_sa_auto_roles = local.enable_ci_sa ? distinct(concat(
    ["roles/runtimeconfig.admin"],
    local.enable_hosting ? ["roles/firebasehosting.admin"] : [],
    # App Hosting は `firebase deploy --only apphosting` (local source) で CI から
    # rollout する。必要ロール:
    #   firebaseapphosting.admin   : build / rollout / traffic の作成
    #   iam.serviceAccountUser     : compute SA (firebase-app-hosting-compute) を act-as
    #   iam.serviceAccountCreator  : firebase CLI は compute SA が既存でも毎回
    #     「ensure (= create)」を試みるため必須 (firebase-tools#8840)。SA は terraform が
    #     先に作るので create は 409 で握り潰されるが、create 権限自体は要る。
    #   resourcemanager.projectIamAdmin : firebase CLI の compute SA ensure は SA 作成後に
    #     プロジェクト IAM を書き換える (projects.setIamPolicy) ため必須。これは Owner 級の
    #     強い権限 (= 任意ロールを誰にでも付与できる) で、Firebase 公式の「最初の backend は
    #     Owner が作る」要件の実体。CLI デプロイ (option ③) を CI から回すには避けられないが、
    #     CI SA が実質 Owner 相当になる点はトレードオフとして許容している (ユーザー判断)。
    local.enable_app_hosting ? ["roles/firebaseapphosting.admin", "roles/iam.serviceAccountUser", "roles/iam.serviceAccountCreator", "roles/resourcemanager.projectIamAdmin"] : [],
    local.enable_cloud_functions ? ["roles/cloudfunctions.admin", "roles/iam.serviceAccountUser", "roles/artifactregistry.admin"] : [],
    local.enable_firestore ? ["roles/datastore.indexAdmin", "roles/firebaserules.admin"] : [],
    # Data Connect の schema / connector を CI (firebase deploy) でデプロイするために必要。
    #   firebasedataconnect.admin : schemas/connectors API (無いと schemas list 等が 403)
    #   cloudsql.admin            : firebase CLI が deploy 時に Cloud SQL instance を
    #                               確認・構成する (無いと sqladmin instances GET が
    #                               "client is not authorized" 403)
    local.enable_data_connect ? ["roles/firebasedataconnect.admin", "roles/cloudsql.admin"] : [],
    local.enable_storage ? ["roles/firebasestorage.viewer", "roles/storage.objectAdmin", "roles/storage.admin"] : [],
    local.enable_cloud_scheduler ? ["roles/cloudscheduler.admin"] : [],
    local.enable_cloud_tasks ? ["roles/cloudtasks.queueAdmin"] : [],
    local.enable_authentication ? ["roles/firebaseauth.admin"] : [],
    local.enable_secret_manager ? ["roles/secretmanager.admin"] : [],
    local.enable_cloud_run ? ["roles/run.admin"] : [],
    try(local.ci_sa_cfg.additional_roles, []),
  )) : []

  # wif binding 設定の正規化。指定が無ければ null (submodule で binding 作らない)。
  # 指定がある場合は principals[] を {attribute, value} object list に整える。
  ci_sa_wif_raw = try(local.ci_sa_cfg.wif, null)
  ci_sa_wif = local.ci_sa_wif_raw == null ? null : {
    pool_resource_name = local.ci_sa_wif_raw.pool_resource_name
    principals = [
      for p in local.ci_sa_wif_raw.principals : {
        attribute = p.attribute
        value     = p.value
      }
    ]
  }
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
    wif          = local.ci_sa_wif
  } : null

  depends_on = [google_project_service.this]
}

# ---------------------------------------------------------------------------
# Gen2 Cloud Functions – service-agent IAM bindings
#
# Gen2 Functions は内部で Cloud Run / Eventarc / Pub/Sub を使うため、deploy 時に
# 各 service-agent への IAM binding が要る。firebase CLI は自動付与を試みるが、
# CI SA (ci-deploy) に projectIamAdmin が無いと "failed to modify the IAM policy"
# で失敗する。ここで terraform が事前付与し、CI SA に広い IAM 権限を渡さずに済ませる。
#
# 付与内容 (firebase CLI が要求する standard Gen2 + Eventarc bindings):
#   - Pub/Sub service agent          : iam.serviceAccountTokenCreator
#   - Compute default SA (runtime)   : run.invoker, eventarc.eventReceiver
# ---------------------------------------------------------------------------

data "google_project" "this" {
  # cloud_functions 有効時 (gen2 compute SA bindings 用) か、default_compute_sa_roles が
  # 指定された時 (SA email の project number 解決用) に取得する。
  count      = (local.enable_cloud_functions || length(var.default_compute_sa_roles) > 0) ? 1 : 0
  project_id = var.project_id
  depends_on = [google_project_service.this]
}

# Pub/Sub service agent (service-{number}@gcp-sa-pubsub...) を確実に存在させる。
resource "google_project_service_identity" "pubsub" {
  count    = local.enable_cloud_functions ? 1 : 0
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"

  depends_on = [google_project_service.this]
}

locals {
  # Compute Engine 既定 SA (<project-number>-compute@developer)。Gen2 Cloud Functions /
  # 既定 Cloud Run の runtime SA。data source は上記 count 条件で取得される。
  compute_default_sa = length(data.google_project.this) > 0 ? (
    "${data.google_project.this[0].number}-compute@developer.gserviceaccount.com"
  ) : ""
  gen2_compute_sa = local.enable_cloud_functions ? local.compute_default_sa : ""
}

resource "google_project_iam_member" "gen2_pubsub_token_creator" {
  count   = local.enable_cloud_functions ? 1 : 0
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_project_service_identity.pubsub[0].email}"
}

resource "google_project_iam_member" "gen2_compute_run_invoker" {
  count   = local.enable_cloud_functions ? 1 : 0
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${local.gen2_compute_sa}"
}

resource "google_project_iam_member" "gen2_compute_eventarc_receiver" {
  count   = local.enable_cloud_functions ? 1 : 0
  project = var.project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${local.gen2_compute_sa}"
}

# 既定 compute SA への追加 role 付与 (runtime が他 API を叩く用)。
# 例: Gen2 Function (cmn-v2-api-*) が Secret Manager の暗号鍵を読むなら
#     "roles/secretmanager.secretAccessor" (editor には versions.access が無いため別途必要)。
# 専用 runtime SA 未分離の構成では全 Gen2 functions / 既定 Cloud Run に影響する点に注意。
# for_each が空なら compute_default_sa も評価されない (data source も未取得で OK)。
resource "google_project_iam_member" "default_compute_extra" {
  for_each = toset(var.default_compute_sa_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${local.compute_default_sa}"
}
