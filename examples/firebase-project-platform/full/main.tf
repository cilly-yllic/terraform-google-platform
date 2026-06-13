module "firebase_platform" {
  source = "../../../modules/firebase-project-platform"

  project_id      = "my-full-project"
  region          = "asia-northeast1"
  billing_account = "XXXXXX-XXXXXX-XXXXXX"

  # Firebase core
  firebase       = true
  authentication = true
  firestore = {
    location = "asia-northeast1"
    type     = "FIRESTORE_NATIVE"
    databases = [
      { database_id = "analytics-db" },
      { database_id = "logs-db", location = "us-central1" },
    ]
  }
  rtdb = {
    location = "asia-southeast1"
  }
  storage = {
    buckets = [
      { name = "icons" },
      { name = "uploads" },
    ]
    firestore_backup = {
      bucket_name     = "firestore-backups"
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

  data_connect = {
    location   = "asia-northeast1"
    service_id = "my-full-project-dc"
    cloud_sql = {
      instance_id      = "my-full-project-fdc"
      database         = "my-full-project"
      tier             = "db-f1-micro"
      database_version = "POSTGRES_15"
    }
  }

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
