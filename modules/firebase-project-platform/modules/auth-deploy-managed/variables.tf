variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "authorized_domains" {
  description = <<-EOT
    OAuth リダイレクト許可ドメインの最終 list (親モジュールで default マージ済み)。
    空なら attribute を設定せず既存 (Firebase デフォルト) を温存する。
    非空のときは authoritative にこの list で全置換される。
  EOT
  type        = list(string)
  default     = []
}
