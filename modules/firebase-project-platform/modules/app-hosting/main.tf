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
