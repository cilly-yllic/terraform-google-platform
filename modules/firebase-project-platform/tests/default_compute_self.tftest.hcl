# default_compute_sa_self_roles の回帰テスト (mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform
#   terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}

# project number を固定して SA email を検証できるようにする。
override_data {
  target = data.google_project.this
  values = {
    number = "123456789012"
  }
}

variables {
  project_id = "test-project"
}

run "self_roles_omitted_creates_nothing" {
  command = plan

  assert {
    condition     = length(google_service_account_iam_member.default_compute_self) == 0
    error_message = "未指定なのに default_compute_self が作られている (既存 plan に差分が出る)"
  }

  assert {
    condition     = length(data.google_project.this) == 0
    error_message = "未指定なのに google_project data を取得している (既存 plan に差分が出る)"
  }
}

# 既存構成 (cloud_functions 有効、self roles 未指定) に新リソースが増えないこと
run "self_roles_omitted_with_cloud_functions_creates_nothing" {
  command = plan

  variables {
    cloud_functions = true
  }

  assert {
    condition     = length(google_service_account_iam_member.default_compute_self) == 0
    error_message = "cloud_functions 有効・self roles 未指定なのに default_compute_self が作られている"
  }

  assert {
    condition     = !contains(local.all_apis, "iamcredentials.googleapis.com")
    error_message = "self roles 未指定なのに iamcredentials API が有効化対象に入っている"
  }
}

run "self_roles_bind_to_compute_sa_itself" {
  command = plan

  variables {
    default_compute_sa_roles      = ["roles/secretmanager.secretAccessor"]
    default_compute_sa_self_roles = ["roles/iam.serviceAccountTokenCreator"]
  }

  assert {
    condition = (
      google_service_account_iam_member.default_compute_self["roles/iam.serviceAccountTokenCreator"].service_account_id
      == "projects/test-project/serviceAccounts/123456789012-compute@developer.gserviceaccount.com"
    )
    error_message = "role の付与先が既定 compute SA 自身になっていない"
  }

  assert {
    condition = (
      google_service_account_iam_member.default_compute_self["roles/iam.serviceAccountTokenCreator"].member
      == "serviceAccount:123456789012-compute@developer.gserviceaccount.com"
    )
    error_message = "member が既定 compute SA になっていない"
  }

  # project-level には付与しない (他 SA への署名権限を増やさない)
  assert {
    condition     = keys(google_project_iam_member.default_compute_extra) == ["roles/secretmanager.secretAccessor"]
    error_message = "self roles が project-level binding に混入している"
  }

  assert {
    condition     = contains(local.all_apis, "iamcredentials.googleapis.com")
    error_message = "self roles 指定時に iamcredentials API が有効化対象に入っていない"
  }
}
