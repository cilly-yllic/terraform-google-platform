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
  description = "CI deploy service account with pre-computed roles."
  type = object({
    account_id   = string
    display_name = optional(string, "CI/CD Deployment")
    roles        = list(string)
  })
  default = null
}

variable "service_accounts" {
  description = "Service accounts to create."
  type = list(object({
    account_id   = string
    display_name = optional(string, "")
    type         = string
    roles        = optional(list(string), [])
    args         = optional(any, {})
  }))
  default = []
}
