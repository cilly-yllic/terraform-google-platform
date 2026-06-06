variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Default location for buckets."
  type        = string
}

variable "buckets" {
  description = "Additional buckets to create. name is auto-prefixed with {project_id}- unless raw_name = true."
  type = list(object({
    name          = string
    raw_name      = optional(bool, false)
    location      = optional(string, "")
    storage_class = optional(string, "")
    iams = optional(list(object({
      role    = string
      members = list(string)
    })), [])
  }))
  default = []
}

variable "firestore_backup" {
  description = "Firestore backup bucket configuration. null to skip."
  type = object({
    bucket_name     = optional(string, "firestore-backups")
    export_platform = optional(string, "cloud_functions")
    soft_delete_policy = optional(object({
      retention_duration_seconds = number
    }), { retention_duration_seconds = 0 })
  })
  default = null
}
