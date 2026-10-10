# firestore_backup の export SA の回帰テスト (mock provider で plan のみ、認証不要)。
#   cd modules/firebase-project-platform/modules/storage
#   terraform init -backend=false && terraform test
#
# cloud_run の export SA は親 module が解決した compute SA email (var.compute_default_sa) を
# そのまま使う。module 内で data.google_project を読むと、親の depends_on により API 追加時の
# plan で member が unknown → -/+ になる (#146)。

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project  = "test-project"
  location = "asia-northeast1"
}

run "cloud_run_export_uses_passed_compute_sa" {
  command = plan

  variables {
    compute_default_sa = "123456789012-compute@developer.gserviceaccount.com"
    firestore_backup   = { export_platform = "cloud_run" }
  }

  assert {
    condition     = google_project_iam_member.firestore_export[0].member == "serviceAccount:123456789012-compute@developer.gserviceaccount.com"
    error_message = "cloud_run の export SA に渡した compute SA email が使われていない"
  }
}

run "cloud_functions_export_uses_appspot_sa" {
  command = plan

  variables {
    firestore_backup = {}
  }

  assert {
    condition     = google_project_iam_member.firestore_export[0].member == "serviceAccount:test-project@appspot.gserviceaccount.com"
    error_message = "既定 (cloud_functions) の export SA が appspot SA になっていない"
  }
}
