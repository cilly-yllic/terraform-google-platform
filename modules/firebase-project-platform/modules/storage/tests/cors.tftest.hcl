# buckets[].cors の回帰テスト (mock provider で plan のみ、認証不要)。
#   cd modules/firebase-project-platform/modules/storage
#   terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project  = "test-project"
  location = "asia-northeast1"
}

run "cors_omitted_creates_no_block" {
  command = plan

  variables {
    buckets = [{ name = "plain" }]
  }

  assert {
    condition     = length(google_storage_bucket.additional["plain"].cors) == 0
    error_message = "cors を書かないバケットに cors ブロックが生成されている (既存バケットに差分が出る)"
  }
}

run "cors_is_passed_through" {
  command = plan

  variables {
    buckets = [
      {
        name = "releases"
        cors = [{
          origin          = ["https://example.web.app", "https://example.firebaseapp.com"]
          method          = ["GET", "HEAD"]
          response_header = ["Content-Type"]
          max_age_seconds = 300
        }]
      },
      {
        name = "partial"
        cors = [{ origin = ["*"] }, { method = ["GET"] }]
      },
    ]
  }

  assert {
    condition     = length(google_storage_bucket.additional["releases"].cors) == 1
    error_message = "releases に cors ブロックが 1 つ生成されていない"
  }

  assert {
    condition = (
      tolist(google_storage_bucket.additional["releases"].cors[0].origin) == tolist(["https://example.web.app", "https://example.firebaseapp.com"]) &&
      tolist(google_storage_bucket.additional["releases"].cors[0].method) == tolist(["GET", "HEAD"]) &&
      tolist(google_storage_bucket.additional["releases"].cors[0].response_header) == tolist(["Content-Type"]) &&
      google_storage_bucket.additional["releases"].cors[0].max_age_seconds == 300
    )
    error_message = "cors の各項目がそのまま渡っていない"
  }

  assert {
    condition     = length(google_storage_bucket.additional["partial"].cors) == 2
    error_message = "一部項目のみの cors ルールが生成されていない"
  }
}
