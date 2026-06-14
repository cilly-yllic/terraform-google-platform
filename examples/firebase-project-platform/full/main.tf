module "firebase_platform" {
  source = "../../../modules/firebase-project-platform"

  project_id      = "my-full-project"
  region          = "asia-northeast1"
  billing_account = "XXXXXX-XXXXXX-XXXXXX"

  # Firebase core
  firebase       = true
  authentication = true
  # Firestore は array で複数 database を 1 project に持てる。
  # "(default)" を含めるかは利用者判断 (SDK の default 動作を期待するなら含める)。
  firestore = [
    { database_id = "(default)", location = "asia-northeast1", type = "FIRESTORE_NATIVE" },
    { database_id = "analytics-db", location = "us-central1" },
    {
      database_id             = "logs-db"
      location                = "us-central1"
      delete_protection_state = "DELETE_PROTECTION_ENABLED"
      point_in_time_recovery  = true
    },
  ]
  rtdb = {
    location = "asia-southeast1"
  }
  storage = {
    # buckets[].name / firestore_backup.bucket_name は globally unique。
    # 短い base name で衝突回避したい場合は auto_prefix=true で `{project_id}-` を被せる。
    buckets = [
      { name = "icons", auto_prefix = true },   # → "{project_id}-icons"
      { name = "uploads", auto_prefix = true }, # → "{project_id}-uploads"
    ]
    firestore_backup = {
      bucket_name     = "firestore-backups"
      auto_prefix     = true
      export_platform = "cloud_run"
    }
  }
  # Firebase App 登録 (Web / iOS / Android を 1 array で管理)。
  # apps を完全に省略しても hosting / app_hosting があれば "default" 名で
  # type=web を 1 件 auto-create する。
  apps = [
    { name = "main", type = "web", display_name = "Main Web App" },
    { name = "admin", type = "web", display_name = "Admin Console" },
    # iOS / Android の例 (任意 — Web のみで十分なら省略可):
    # {
    #   name      = "main-ios"
    #   type      = "ios"
    #   bundle_id = "com.example.app"
    # },
    # {
    #   name         = "main-android"
    #   type         = "android"
    #   package_name = "com.example.app"
    # },
  ]

  # 複数 hosting site の例。app field は type=web の apps[].name を指す。
  # type=web の apps が 1 件のみなら省略可。
  hosting = [
    { site_id = "my-full-project-web", app = "main" },
    { site_id = "my-full-project-admin", app = "admin" },
  ]

  # 複数 App Hosting backend の例。app field の挙動は hosting と同じ。
  app_hosting = [
    {
      backend_id = "api"
      location   = "asia-northeast1"
      app        = "main"
    },
    {
      backend_id = "jobs"
      location   = "us-central1"
      app        = "main"
      # 外部 Web App を pin したい時は app の代わりに app_id を指定:
      # app_id = "1:XXXXX:web:abc123"
    },
  ]

  # Data Connect は services array。複数 service が同 cloud_sql.instance_id を
  # 指せば自動 dedup されて 1 Cloud SQL Instance に集約 (コスト最適化)。
  # 同 instance_id を共有する entries 間で tier / database_version /
  # deletion_protection / location は一致必須 (precondition で plan-time check)。
  data_connect = [
    {
      service_id = "main"
      location   = "asia-northeast1"
      cloud_sql = {
        instance_id      = "shared-fdc"
        database         = "main"
        tier             = "db-custom-2-4096"
        database_version = "POSTGRES_15"
      }
    },
    {
      # 同じ instance_id を指す → 自動で 1 instance に集約、別 database が作られる
      service_id = "analytics"
      cloud_sql = {
        instance_id = "shared-fdc"
        database    = "analytics"
      }
    },
    {
      # 別の instance_id → 別の Cloud SQL Instance (別 region で独立)
      service_id = "jobs"
      location   = "us-central1"
      cloud_sql = {
        instance_id = "jobs-fdc"
        database    = "jobs"
        tier        = "db-f1-micro"
      }
    },
  ]

  # Firebase extensions
  fcm           = true
  remote_config = true
  app_check     = true
  crashlytics   = true
  performance   = true
  analytics     = true
  extensions    = true

  # GCP services
  secret_manager  = true
  cloud_tasks     = { location = "asia-northeast1" }
  cloud_scheduler = { location = "asia-northeast1" }
  pubsub          = true
  eventarc        = { location = "asia-northeast1" }
  cloud_run       = true
  cloud_functions = true

  # Additional APIs
  additional_apis = [
    "iap.googleapis.com",
  ]

  # Users
  users = [
    {
      email  = "dev-lead@example.com"
      role   = "editor"
      deploy = true
    },
    {
      email = "viewer@example.com"
      role  = "viewer"
    },
  ]

  # CI Service Account (auto-determined roles from enabled features)
  ci_service_account = {
    account_id       = "ci-deploy"
    display_name     = "CI/CD Deployment"
    additional_roles = ["roles/viewer"]
  }

  # Additional service accounts (manual role assignment)
  service_accounts = [
    {
      account_id   = "app-runtime"
      display_name = "App Hosting Runtime SA"
      type         = "deploy"
      args = {
        hosting   = false
        functions = false
        firestore = true
        storage   = true
        scheduler = false
        tasks     = false
        blocking  = false
      }
    },
  ]
}
