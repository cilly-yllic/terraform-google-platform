resource "google_identity_platform_config" "this" {
  provider = google-beta
  project  = var.project

  # OAuth リダイレクト許可ドメイン (Google/Apple 等の signInWithPopup/Redirect、
  # メールリンク認証で使用)。authoritative (全置換) かつ computed なので、空のときは
  # null を渡して既存 (Firebase デフォルト: localhost / *.firebaseapp.com / *.web.app)
  # を温存する。デフォルトのマージ判断は親モジュールが行い、ここは最終 list を受けるだけ。
  authorized_domains = length(var.authorized_domains) > 0 ? var.authorized_domains : null

  dynamic "blocking_functions" {
    for_each = (var.blocking_functions.before_create != "" || var.blocking_functions.before_sign_in != "") ? [1] : []
    content {
      dynamic "triggers" {
        for_each = var.blocking_functions.before_create != "" ? [var.blocking_functions.before_create] : []
        content {
          event_type   = "beforeCreate"
          function_uri = triggers.value
        }
      }
      dynamic "triggers" {
        for_each = var.blocking_functions.before_sign_in != "" ? [var.blocking_functions.before_sign_in] : []
        content {
          event_type   = "beforeSignIn"
          function_uri = triggers.value
        }
      }
    }
  }
}
