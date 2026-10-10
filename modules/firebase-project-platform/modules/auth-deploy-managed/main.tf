# blocking functions の trigger を firebase deploy の自動登録に任せる Identity Platform
# config。modules/auth (terraform 管理) と同じ singleton を扱い、root module が
# authentication.blocking_functions.managed_by でどちらか一方だけを呼ぶ。
#
# blocking_functions は provider schema 上 Optional のみ (Computed でない) なので、
# ブロックを書かないだけでは deploy 登録分が「設定に無い」として PATCH で消える。
# ignore_changes は条件で切り替えられないため、modules/auth とは別 module にしている
# (modules/auth の resource アドレスは v1.3.0 から変えない)。
resource "google_identity_platform_config" "this" {
  provider = google-beta
  project  = var.project

  # modules/auth と同じ扱い。空なら null で既存 (Firebase デフォルト) を温存する。
  authorized_domains = length(var.authorized_domains) > 0 ? var.authorized_domains : null

  lifecycle {
    # firebase deploy が登録した beforeCreate / beforeSignIn の trigger を触らない。
    ignore_changes = [blocking_functions]
  }
}
