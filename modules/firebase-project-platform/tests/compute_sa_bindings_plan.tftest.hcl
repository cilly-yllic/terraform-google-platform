# 既定 compute SA の binding が、API 構成の変わる plan でも置き換え (-/+) にならないことの
# 回帰テスト (#146。mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test
#
# 既存構成を apply したあと、API を追加する plan を流す。data.google_project が
# google_project_service.this (feature API) に依存していると読み込みが apply まで遅延し、
# member が unknown (= ForceNew で -/+) になる。plan 時点で member が確定していることを確かめる。
# (mock provider は ForceNew を評価しないため、member が known であることを代替指標にする)

mock_provider "google" {}
mock_provider "google-beta" {}

override_data {
  target = data.google_project.this
  values = {
    number = "123456789012"
  }
}

variables {
  project_id               = "test-project"
  cloud_functions          = true
  default_compute_sa_roles = ["roles/secretmanager.secretAccessor"]
  storage = {
    firestore_backup = {
      export_platform = "cloud_run"
    }
  }
}

run "initial_apply" {
  command = apply
}

run "api_change_keeps_compute_sa_members_known" {
  command = plan

  variables {
    additional_apis               = ["iap.googleapis.com"]
    default_compute_sa_self_roles = ["roles/iam.serviceAccountTokenCreator"]
  }

  # storage (firestore_backup.export_platform = "cloud_run") はこの値をそのまま member に使う
  assert {
    condition     = local.compute_default_sa == "123456789012-compute@developer.gserviceaccount.com"
    error_message = "compute SA email が plan 時点で確定していない (data.google_project の読み込みが遅延している)"
  }

  assert {
    condition     = google_project_iam_member.gen2_compute_run_invoker[0].member == "serviceAccount:123456789012-compute@developer.gserviceaccount.com"
    error_message = "gen2_compute_run_invoker の member が plan 時点で確定していない"
  }

  assert {
    condition     = google_project_iam_member.gen2_compute_eventarc_receiver[0].member == "serviceAccount:123456789012-compute@developer.gserviceaccount.com"
    error_message = "gen2_compute_eventarc_receiver の member が plan 時点で確定していない"
  }

  assert {
    condition     = google_project_iam_member.default_compute_extra["roles/secretmanager.secretAccessor"].member == "serviceAccount:123456789012-compute@developer.gserviceaccount.com"
    error_message = "default_compute_extra の member が plan 時点で確定していない"
  }

  assert {
    condition     = google_service_account_iam_member.default_compute_self["roles/iam.serviceAccountTokenCreator"].service_account_id == "projects/test-project/serviceAccounts/123456789012-compute@developer.gserviceaccount.com"
    error_message = "default_compute_self の service_account_id が plan 時点で確定していない"
  }

  # base API は別リソース (google_project_service.base) に分かれ、enabled_apis は従来どおり全件を返す
  assert {
    condition     = contains(output.enabled_apis, "cloudresourcemanager.googleapis.com") && contains(output.enabled_apis, "iap.googleapis.com")
    error_message = "enabled_apis に base API / 追加 API が含まれていない"
  }
}
