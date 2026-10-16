# SA への付与 (app_hosting_compute_sa / default_compute_sa / service_accounts[] の self_roles・bucket_roles) の
# 回帰テスト (mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test

mock_provider "google" {
  mock_resource "google_service_account" {
    defaults = {
      name   = "projects/test-project/serviceAccounts/firebase-app-hosting-compute@test-project.iam.gserviceaccount.com"
      member = "serviceAccount:firebase-app-hosting-compute@test-project.iam.gserviceaccount.com"
    }
  }
}
mock_provider "google-beta" {}

override_data {
  target = data.google_project.this
  values = {
    number = "123456789012"
  }
}

variables {
  project_id = "test-project"
  apps = [
    { name = "web", type = "web" },
  ]
  app_hosting = [
    { backend_id = "web-app", location = "asia-east1", app = "web" },
  ]
  storage = {
    buckets = [
      { name = "media" },
      { name = "docs", auto_prefix = true },
      { name = "backups" },
    ]
  }
}

# 未指定なら新しい付与は作らない (v1 から移行した既存構成に差分を出さない)
run "omitted_creates_nothing" {
  command = plan

  assert {
    condition = (
      length(google_service_account_iam_member.app_hosting_compute_self) == 0 &&
      length(google_storage_bucket_iam_member.service_account_bucket) == 0
    )
    error_message = "未指定なのに self / bucket の付与が作られている"
  }
}

run "app_hosting_grants_go_to_each_scope" {
  command = apply

  variables {
    app_hosting_compute_sa = {
      roles      = ["roles/cloudtasks.enqueuer"]
      self_roles = ["roles/iam.serviceAccountUser"]
      bucket_roles = [
        { bucket = "media", roles = ["roles/storage.objectUser"] },
        { bucket = "docs", roles = ["roles/storage.objectUser", "roles/storage.objectViewer"] },
      ]
    }
  }

  # project-level は roles だけ (self / bucket の role が混ざらない)
  assert {
    condition     = keys(google_project_iam_member.app_hosting_compute_extra) == ["roles/cloudtasks.enqueuer"]
    error_message = "project-level の付与に self / bucket の role が混入している"
  }

  # self_roles は共有 compute SA 自身が対象
  assert {
    condition = (
      google_service_account_iam_member.app_hosting_compute_self["roles/iam.serviceAccountUser"].service_account_id
      == "projects/test-project/serviceAccounts/firebase-app-hosting-compute@test-project.iam.gserviceaccount.com"
    )
    error_message = "self_roles の付与先が共有 compute SA 自身になっていない"
  }

  # bucket_roles は入力の名前で書き、auto_prefix 後の実名に付与する
  assert {
    condition = (
      google_storage_bucket_iam_member.service_account_bucket["app_hosting_compute|media|roles/storage.objectUser"].bucket == "media" &&
      google_storage_bucket_iam_member.service_account_bucket["app_hosting_compute|docs|roles/storage.objectUser"].bucket == "test-project-docs" &&
      google_storage_bucket_iam_member.service_account_bucket["app_hosting_compute|docs|roles/storage.objectViewer"].bucket == "test-project-docs"
    )
    error_message = "bucket_roles の付与先バケットが storage.buckets の実名になっていない"
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.service_account_bucket) == 3
    error_message = "bucket_roles に書いていないバケットにも付与している"
  }
}

run "default_compute_bucket_grants" {
  command = apply

  variables {
    default_compute_sa = {
      bucket_roles = [
        { bucket = "backups", roles = ["roles/storage.objectViewer"] },
      ]
    }
  }

  assert {
    condition = (
      google_storage_bucket_iam_member.service_account_bucket["default_compute|backups|roles/storage.objectViewer"].member
      == "serviceAccount:123456789012-compute@developer.gserviceaccount.com"
    )
    error_message = "default_compute_sa.bucket_roles の member が既定 compute SA になっていない"
  }
}

run "unknown_bucket_is_rejected" {
  command = plan

  variables {
    app_hosting_compute_sa = {
      bucket_roles = [
        { bucket = "not-declared", roles = ["roles/storage.objectUser"] },
      ]
    }
  }

  expect_failures = [
    google_storage_bucket_iam_member.service_account_bucket,
  ]
}

run "service_accounts_grants" {
  command = apply

  variables {
    service_accounts = [{
      account_id   = "vm-runner"
      type         = "runtime"
      roles        = ["roles/logging.logWriter"]
      self_roles   = ["roles/iam.serviceAccountTokenCreator"]
      bucket_roles = [{ bucket = "media", roles = ["roles/storage.objectViewer"] }]
    }]
  }

  assert {
    condition = (
      toset(module.iam.service_account_roles["vm-runner"]) == toset(["roles/logging.logWriter"])
    )
    error_message = "service_accounts[].roles (project-level) に self / bucket の role が混入している"
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.service_account_bucket) == 1
    error_message = "service_accounts[].bucket_roles の付与が作られていない"
  }

  assert {
    condition     = google_storage_bucket_iam_member.service_account_bucket["vm-runner|media|roles/storage.objectViewer"].bucket == "media"
    error_message = "service_accounts[].bucket_roles の付与先バケットが違う"
  }

  assert {
    condition     = contains(local.all_apis, "iamcredentials.googleapis.com")
    error_message = "service_accounts[].self_roles 指定時に iamcredentials API が有効化対象に入っていない"
  }
}

# 共有 SA を作らない構成 (App Hosting 無効) では、app_hosting_compute_sa.self_roles は no-op で API も足さない
run "app_hosting_self_roles_without_shared_sa_is_noop" {
  command = plan

  variables {
    app_hosting = null
    app_hosting_compute_sa = {
      self_roles = ["roles/iam.serviceAccountUser"]
    }
  }

  assert {
    condition     = length(google_service_account_iam_member.app_hosting_compute_self) == 0
    error_message = "共有 SA が無いのに app_hosting_compute_self が作られている"
  }

  assert {
    condition     = !contains(local.all_apis, "iamcredentials.googleapis.com")
    error_message = "共有 SA が無いのに iamcredentials API が有効化対象に入っている"
  }
}

# 同じ role を 2 回書いても、ほかの付与と同じく重複を除いて plan できる
run "duplicate_roles_are_deduplicated" {
  command = plan

  variables {
    service_accounts = [{
      account_id   = "vm-runner"
      type         = "runtime"
      self_roles   = ["roles/iam.serviceAccountTokenCreator", "roles/iam.serviceAccountTokenCreator"]
      bucket_roles = [{ bucket = "media", roles = ["roles/storage.objectViewer", "roles/storage.objectViewer"] }]
    }]
  }

  assert {
    condition     = length(google_storage_bucket_iam_member.service_account_bucket) == 1
    error_message = "bucket_roles の重複した role が 1 つにまとまっていない"
  }
}
