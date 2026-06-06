variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Default Firestore location."
  type        = string
}

variable "type" {
  description = "Default database type."
  type        = string
  default     = "FIRESTORE_NATIVE"

  validation {
    condition     = contains(["FIRESTORE_NATIVE", "DATASTORE_MODE"], var.type)
    error_message = "type must be FIRESTORE_NATIVE or DATASTORE_MODE."
  }
}

variable "delete_protection_state" {
  description = "Delete protection state for the default database."
  type        = string
  default     = "DELETE_PROTECTION_DISABLED"

  validation {
    condition     = contains(["DELETE_PROTECTION_DISABLED", "DELETE_PROTECTION_ENABLED"], var.delete_protection_state)
    error_message = "delete_protection_state must be DELETE_PROTECTION_DISABLED or DELETE_PROTECTION_ENABLED."
  }
}

variable "point_in_time_recovery" {
  description = "Enable point-in-time recovery for the default database."
  type        = bool
  default     = false
}

variable "databases" {
  description = "Additional Firestore databases to create."
  type = list(object({
    database_id             = string
    location                = optional(string, "")
    type                    = optional(string, "FIRESTORE_NATIVE")
    delete_protection_state = optional(string, "DELETE_PROTECTION_DISABLED")
    point_in_time_recovery  = optional(bool, false)
  }))
  default = []
}
