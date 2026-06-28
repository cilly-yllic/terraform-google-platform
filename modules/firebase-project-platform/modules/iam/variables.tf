variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "users" {
  description = "Project IAM members."
  type = list(object({
    email  = string
    role   = optional(string, "viewer")
    deploy = optional(bool, false)
  }))
  default = []
}

variable "ci_service_account" {
  # wif は optional。null なら workloadIdentityUser binding を作らず (= default 動作、
  # 外部 CI から impersonate するなら手動で SA key 発行などが必要)。
  # 設定する場合は project-bootstrap が用意済みの WIF Pool を参照する。
  # principals は {attribute, value} ペアの list で provider-agnostic
  # (github=`repository`, terraform_cloud=`terraform_workspace`, gitlab=`project_path` 等)。
  description = "CI deploy service account with pre-computed roles + optional WIF principalSet bindings."
  type = object({
    account_id   = string
    display_name = optional(string, "CI/CD Deployment")
    roles        = list(string)
    wif = optional(object({
      pool_resource_name = string
      principals = list(object({
        attribute = string
        value     = string
      }))
    }), null)
  })
  default = null
}

variable "service_accounts" {
  description = "Service accounts to create. Optional per-SA WIF principalSet binding (same shape as ci_service_account.wif) for keyless impersonation from external CI."
  type = list(object({
    account_id   = string
    display_name = optional(string, "")
    type         = string
    roles        = optional(list(string), [])
    args         = optional(any, {})
    wif = optional(object({
      pool_resource_name = string
      principals = list(object({
        attribute = string
        value     = string
      }))
    }), null)
  }))
  default = []
}
