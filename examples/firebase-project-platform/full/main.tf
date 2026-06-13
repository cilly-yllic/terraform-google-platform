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
  # Web App は省略可 (hosting / app_hosting がいるので "default" 名で自動作成される)。
  # 明示するなら以下のように複数定義もできる:
  #   web_app = [
  #     { name = "main", display_name = "Main" },
  #     { name = "admin", display_name = "Admin Console" },
  #   ]

  # 複数 hosting site の例。web_app 単数なら参照省略可。
  hosting = [
    { site_id = "my-full-project-web" },
    { site_id = "my-full-project-staging" },
  ]

  # 複数 App Hosting backend の例。同じく web_app 単数なら参照省略可。
  app_hosting = [
    {
      backend_id = "api"
      location   = "asia-northeast1"
    },
    {
      backend_id = "jobs"
      location   = "us-central1"
      # 外部 Web App を pin したい時は web_app の代わりに app_id を指定:
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
