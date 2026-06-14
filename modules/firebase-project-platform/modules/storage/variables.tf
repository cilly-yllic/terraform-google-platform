variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Default location for buckets."
  type        = string
}

variable "buckets" {
  # GCS bucket は globally unique。`auto_prefix = true` で `{project_id}-{name}`
  # に組み立てる。default は false (= `name` をそのまま使う)。
  description = "Additional buckets to create. name is used verbatim; set auto_prefix = true to wrap with {project_id}- for global uniqueness."
  type = list(object({
    name          = string
    auto_prefix   = optional(bool, false)
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
  # bucket_name も globally unique。`auto_prefix = true` で `{project_id}-` を付与。
  # default は false (= bucket_name をそのまま使う) — buckets[] と統一。
  description = "Firestore backup bucket configuration. null to skip. bucket_name is used verbatim; set auto_prefix = true to wrap with {project_id}-."
  type = object({
    bucket_name     = optional(string, "firestore-backups")
    auto_prefix     = optional(bool, false)
    export_platform = optional(string, "cloud_functions")
    soft_delete_policy = optional(object({
      retention_duration_seconds = number
    }), { retention_duration_seconds = 0 })
  })
  default = null
}
