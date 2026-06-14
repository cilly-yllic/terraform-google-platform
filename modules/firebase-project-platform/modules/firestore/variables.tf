variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "default_location" {
  description = "Fallback location used when an entry omits location."
  type        = string
}

variable "databases" {
  description = <<-EOT
    Firestore databases (1 project に複数 DB)。
    各 entry は (default) database を含む全 DB を表現する。

      database_id              = 必須。"(default)" を含めるかは利用者判断。
                                 SDK の default 動作を期待するなら含める。
      location                 = optional (省略時 var.default_location)
      type                     = optional ("FIRESTORE_NATIVE" | "DATASTORE_MODE", default "FIRESTORE_NATIVE")
      delete_protection_state  = optional ("DELETE_PROTECTION_DISABLED" | "_ENABLED", default disabled)
      point_in_time_recovery   = optional (bool, default false)
  EOT
  type = list(object({
    database_id             = string
    location                = optional(string, "")
    type                    = optional(string, "FIRESTORE_NATIVE")
    delete_protection_state = optional(string, "DELETE_PROTECTION_DISABLED")
    point_in_time_recovery  = optional(bool, false)
  }))
  default = []

  validation {
    condition = alltrue([
      for db in var.databases :
      contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], db.type)
    ])
    error_message = "firestore[].type must be FIRESTORE_NATIVE or DATASTORE_MODE."
  }

  validation {
    condition = alltrue([
      for db in var.databases :
      contains(["DELETE_PROTECTION_DISABLED", "DELETE_PROTECTION_ENABLED"], db.delete_protection_state)
    ])
    error_message = "firestore[].delete_protection_state must be DELETE_PROTECTION_DISABLED or DELETE_PROTECTION_ENABLED."
  }
}

variable "apply_default_rules" {
  description = "If true, attach a project-level deny-all initial ruleset to cloud.firestore. Disable when bootstrapping rules via Firebase CLI."
  type        = bool
  default     = true
}
