resource "google_firebase_app_hosting_backend" "this" {
  provider         = google-beta
  project          = var.project
  location         = var.location
  backend_id       = var.backend_id
  app_id           = var.app_id
  service_account  = var.service_account
  serving_locality = var.serving_locality

  # git 連携 (Developer Connect) backend の場合のみ codebase を設定する。
  # repository は親が作成した google_developer_connect_git_repository_link の
  # フルリソース名 (projects/.../gitRepositoryLinks/...)。codebase_repository が
  # 空 = bare backend (従来どおり repo 非連携) なので codebase ブロックを出さない。
  dynamic "codebase" {
    for_each = var.codebase_repository != "" ? [1] : []
    content {
      repository     = var.codebase_repository
      root_directory = var.root_directory != "" ? var.root_directory : null
    }
  }
}

# 自動ロールアウトの監視ブランチ設定。
#
# 設計 (state 汚染回避):
#   - rollout_policy だけを管理し、target.splits は絶対に書かない。
#     target は build ID を手動 pin するため push のたびに新 build が出来て drift する。
#   - 実際の traffic 配分は current.splits (output-only) で App Hosting が push ごとに
#     自動更新するが、terraform は読むだけで書きに行かない → drift しない。
#   - rollout_branch が空なら自動ロールアウトしない (traffic リソース自体を作らない)。
#
# 前提: git 連携 backend (codebase 設定済み) でのみ意味を持つ。
resource "google_firebase_app_hosting_traffic" "this" {
  count    = var.rollout_branch != "" ? 1 : 0
  provider = google-beta
  project  = var.project
  location = var.location
  backend  = google_firebase_app_hosting_backend.this.backend_id

  rollout_policy {
    codebase_branch = var.rollout_branch
  }
}
