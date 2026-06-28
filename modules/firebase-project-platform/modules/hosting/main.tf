resource "google_firebase_hosting_site" "this" {
  provider = google-beta
  project  = var.project
  site_id  = var.site_id
  app_id   = var.app_id
}

# Custom domain (複数可、空なら作らない)。
# DNS レコード登録は別レイヤで行う前提なので wait_dns_verification=false にして
# DNS 未設定でも apply がブロック/タイムアウトしないようにする。検証は Firebase 側で
# 非同期に進む。必要な DNS レコードは output.required_dns_updates で参照可能。
# for_each キーはドメイン名そのもの (state 安定用)。
resource "google_firebase_hosting_custom_domain" "this" {
  for_each = toset(var.custom_domains)

  provider              = google-beta
  project               = var.project
  site_id               = google_firebase_hosting_site.this.site_id
  custom_domain         = each.value
  wait_dns_verification = false
}
