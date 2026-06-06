variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Data Connect service location."
  type        = string
}

variable "service_id" {
  description = "Data Connect service ID."
  type        = string
  default     = ""
}

variable "cloud_sql" {
  description = "Cloud SQL instance configuration for Data Connect. null to skip."
  type = object({
    instance_id         = optional(string, "")
    database            = optional(string, "")
    tier                = optional(string, "db-f1-micro")
    database_version    = optional(string, "POSTGRES_15")
    deletion_protection = optional(bool, false)
  })
  default = null
}
