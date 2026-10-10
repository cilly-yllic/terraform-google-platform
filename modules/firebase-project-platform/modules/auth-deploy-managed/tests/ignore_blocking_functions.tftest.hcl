# mock provider のみ、認証不要。
#   cd modules/firebase-project-platform/modules/auth-deploy-managed
#   terraform init -backend=false && terraform test
#
# deploy が登録した trigger を ignore_changes で温存できること自体は mock では
# 再現できない (blocking_functions は Computed でなく override できない)。
# 実 provider + trigger 登録済み state の plan -refresh=false で No changes を確認済み (#154)。

mock_provider "google-beta" {}

variables {
  project = "test-project"
}

run "no_blocking_functions_block" {
  command = plan

  assert {
    condition     = length(google_identity_platform_config.this.blocking_functions) == 0
    error_message = "deploy 管理では blocking_functions を設定しない"
  }
}

run "authorized_domains_still_managed" {
  command = plan

  variables {
    authorized_domains = ["example.com", "localhost"]
  }

  assert {
    condition     = google_identity_platform_config.this.authorized_domains == tolist(["example.com", "localhost"])
    error_message = "deploy 管理でも authorized_domains は terraform で管理する"
  }
}
