variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "backend_id" {
  description = "App Hosting backend ID (= Firebase Console title). Project-unique. [a-z0-9-]{4,32}."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}[a-z0-9]$", var.backend_id))
    error_message = "backend_id must be 4-32 chars, lowercase alphanumeric and hyphens, start with a letter, end with letter or digit."
  }
}

variable "location" {
  description = "App Hosting backend location."
  type        = string
}

variable "app_id" {
  description = "Firebase Web App ID to link this backend to."
  type        = string
}

variable "service_account" {
  description = "Service account email for the App Hosting backend (already resolved by parent)."
  type        = string
}

variable "serving_locality" {
  description = "Serving locality for the App Hosting backend."
  type        = string
  default     = "GLOBAL_ACCESS"

  validation {
    condition     = contains(["GLOBAL_ACCESS", "REGION_LOCKED"], var.serving_locality)
    error_message = "serving_locality must be GLOBAL_ACCESS or REGION_LOCKED."
  }
}

variable "codebase_repository" {
  description = <<-EOT
    git 連携 backend の場合、親が作成した Developer Connect git_repository_link の
    フルリソース名 (projects/.../connections/.../gitRepositoryLinks/...)。
    空文字なら bare backend (repo 非連携) として codebase ブロックを出さない。
  EOT
  type        = string
  default     = ""
}

variable "root_directory" {
  description = "リポジトリ内の web app ルート (例: apps/web)。空ならリポジトリ直下。"
  type        = string
  default     = ""
}

variable "rollout_branch" {
  description = <<-EOT
    自動ロールアウトの監視ブランチ。指定すると当該ブランチへの push で App Hosting が
    build & rollout を実行する。空なら自動ロールアウトしない (traffic リソース未作成)。
  EOT
  type        = string
  default     = ""
}
