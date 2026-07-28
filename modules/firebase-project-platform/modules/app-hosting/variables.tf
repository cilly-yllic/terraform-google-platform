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

variable "custom_domains" {
  description = "Custom domains to register for this backend (複数可)。空 list なら作らない。DNS 登録は別レイヤ前提。"
  type        = list(string)
  default     = []
}

variable "environment" {
  # backend の「環境名」。firebase CLI が rollout 時に apphosting.<environment>.yaml
  # (環境別の runConfig / env vars) を選択するためのラベル。Console の backend 設定に
  # ある "environment" と同じもの。null (既定) なら apphosting.yaml のみが使われる。
  # provider 上は mutable (変更しても backend 再作成にはならない)。
  description = "Environment name of the backend (selects apphosting.<environment>.yaml at deploy time). null なら未設定。"
  type        = string
  default     = null
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
