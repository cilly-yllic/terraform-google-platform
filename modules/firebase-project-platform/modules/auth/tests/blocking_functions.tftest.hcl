# manage_blocking_functions による resource の出し分けの回帰テスト (#153)。
# mock provider のみ、認証不要。
#   cd modules/firebase-project-platform/modules/auth
#   terraform init -backend=false && terraform test
#
# deploy が登録した trigger を ignore_changes で温存できること自体は mock では
# 再現できない (blocking_functions は Computed でなく override できない)。

mock_provider "google-beta" {}

variables {
  project = "test-project"
}

run "terraform_managed_by_default" {
  command = plan

  variables {
    blocking_functions = {
      before_create = "https://example.com/before-create"
    }
  }

  assert {
    condition     = length(google_identity_platform_config.this) == 1 && length(google_identity_platform_config.deploy_managed) == 0
    error_message = "既定は terraform 管理の resource (this) を使う"
  }

  assert {
    condition     = one(google_identity_platform_config.this[0].blocking_functions[0].triggers).event_type == "beforeCreate"
    error_message = "terraform 管理では URI の trigger を設定する"
  }
}

run "terraform_managed_without_uri_has_no_block" {
  command = plan

  assert {
    condition     = length(google_identity_platform_config.this[0].blocking_functions) == 0
    error_message = "URI が空なら blocking_functions ブロックを出さない (従来どおり)"
  }
}

run "deploy_managed" {
  command = plan

  variables {
    manage_blocking_functions = false
  }

  assert {
    condition     = length(google_identity_platform_config.this) == 0 && length(google_identity_platform_config.deploy_managed) == 1
    error_message = "manage_blocking_functions = false は deploy_managed resource を使う"
  }
}

run "deploy_managed_keeps_authorized_domains" {
  command = plan

  variables {
    manage_blocking_functions = false
    authorized_domains        = ["example.com", "localhost"]
  }

  assert {
    condition     = google_identity_platform_config.deploy_managed[0].authorized_domains == tolist(["example.com", "localhost"])
    error_message = "deploy 管理でも authorized_domains は terraform で管理する"
  }
}

run "deploy_managed_with_uri_rejected" {
  command = plan

  variables {
    manage_blocking_functions = false
    blocking_functions = {
      before_sign_in = "https://example.com/before-sign-in"
    }
  }

  expect_failures = [google_identity_platform_config.deploy_managed]
}
