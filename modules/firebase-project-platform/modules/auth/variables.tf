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

variable "blocking_functions" {
  description = "Blocking functions configuration."
  type = object({
    before_create  = optional(string, "")
    before_sign_in = optional(string, "")
  })
  default = {}
}

variable "manage_blocking_functions" {
  description = <<-EOT
    blocking functions を terraform で管理するか。
    true  : blocking_functions の URI で trigger を authoritative に管理する
            (空なら trigger 無し。deploy が登録した trigger は次の apply で消える)
    false : firebase deploy の自動登録に任せ、trigger を ignore_changes で温存する
            (blocking_functions は空であること)
  EOT
  type        = bool
  default     = true
}
