# blocking functions の管理モードで resource を出し分ける。
#   - this           : terraform 管理。blocking_functions は var の URI で authoritative
#   - deploy_managed : firebase deploy 管理。deploy が登録した trigger を
#                      ignore_changes で温存する
# blocking_functions は provider schema 上 Optional のみ (Computed でない) なので、
# ブロックを書かないだけでは deploy 登録分が「設定に無い」として PATCH で消える。
# ignore_changes は条件で切り替えられないため 2 resource に分けている。
#
# モードを切り替えると state のアドレスが変わる。旧アドレスの destroy は provider
# 側で no-op (config は削除不可のため state から外れるだけ) だが、新アドレスは
# create (initializeAuth) が既存 config と衝突するので import が要る
# (root の authentication.import_existing)。

moved {
  from = google_identity_platform_config.this
  to   = google_identity_platform_config.this[0]
}

resource "google_identity_platform_config" "this" {
  count = var.manage_blocking_functions ? 1 : 0

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

resource "google_identity_platform_config" "deploy_managed" {
  count = var.manage_blocking_functions ? 0 : 1

  provider = google-beta
  project  = var.project

  # this と同じ扱い (上のコメント参照)。
  authorized_domains = length(var.authorized_domains) > 0 ? var.authorized_domains : null

  lifecycle {
    # firebase deploy が登録した beforeCreate / beforeSignIn の trigger を触らない。
    ignore_changes = [blocking_functions]

    precondition {
      condition     = var.blocking_functions.before_create == "" && var.blocking_functions.before_sign_in == ""
      error_message = "manage_blocking_functions = false (deploy 管理) では blocking_functions の URI を指定できない。"
    }
  }
}
