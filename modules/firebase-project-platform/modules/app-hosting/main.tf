# App Hosting backend (bare)。
# terraform は backend の「箱」と compute SA だけを用意し、実際のコードのデプロイ
# (build / rollout) は firebase CLI (`firebase deploy --only apphosting`, local source) が
# 担う。build / rollout は terraform 管理外の別レイヤなので state 汚染は起きない。
resource "google_firebase_app_hosting_backend" "this" {
  provider         = google-beta
  project          = var.project
  location         = var.location
  backend_id       = var.backend_id
  app_id           = var.app_id
  service_account  = var.service_account
  serving_locality = var.serving_locality
}

# Custom domain (複数可、空なら作らない)。
# 作成自体は DNS 検証を待たずに通る (検証は Firebase 側で非同期に進む)。DNS レコード
# 登録は別レイヤ前提で、必要なレコードは output.required_dns_updates で参照できる。
# for_each キーはドメイン名そのもの (state 安定用)。
resource "google_firebase_app_hosting_domain" "this" {
  for_each = toset(var.custom_domains)

  provider  = google-beta
  project   = var.project
  location  = var.location
  backend   = google_firebase_app_hosting_backend.this.backend_id
  domain_id = each.value
}
