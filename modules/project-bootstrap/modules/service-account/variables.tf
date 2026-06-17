# SA はターゲット (作成した firebase 用) プロジェクト内に作る。infra に
# `project 数 × env 数` 分の SA が溜まる問題を避けるため (GCP は 1 project
# あたり SA 100 個上限)。これにより quota / 課金 / 権限 / ライフサイクルが
# そのプロジェクトに閉じる。関連: modules/project-bootstrap/main.tf
variable "project_id" {
  description = "The project ID where the service account is created (= the target project)"
  type        = string
}

variable "service_account_id" {
  description = "The service account ID (e.g. terraform-example-prd)"
  type        = string
}
