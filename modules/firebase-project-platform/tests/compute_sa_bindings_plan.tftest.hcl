# 既定 compute SA の binding が、API 構成の変わる plan でも置き換え (-/+) にならないことの
# 回帰テスト (#146。mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test
#
# 空の state から plan すると google_project_service.this は全件「作成予定」になり、
# API 構成が変わる plan と同じ状況になる。data.google_project に depends_on があると
# 読み込みが apply まで遅延し、member が unknown になる (= ForceNew で -/+)。
# plan 時点で member が確定していることを確かめる。

mock_provider "google" {}
mock_provider "google-beta" {}

override_data {
  target = data.google_project.this
  values = {
    number = "123456789012"
  }
}

variables {
  project_id                    = "test-project"
  cloud_functions               = true
  additional_apis               = ["iamcredentials.googleapis.com"]
  default_compute_sa_roles      = ["roles/secretmanager.secretAccessor"]
  default_compute_sa_self_roles = ["roles/iam.serviceAccountTokenCreator"]
}

run "compute_sa_members_are_known_at_plan" {
  command = plan

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
}
