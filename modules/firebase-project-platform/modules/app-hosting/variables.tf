variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "App Hosting backend location."
  type        = string
}

variable "app_id" {
  description = "Firebase Web App ID for the App Hosting backend."
  type        = string
}

variable "service_account" {
  description = "Service account email for the App Hosting backend."
  type        = string
}

variable "serving_locality" {
  description = "Serving locality for the App Hosting backend."
  type        = string
  default     = "GLOBAL_ACCESS"

  validation {
    condition     = contains(["GLOBAL_ACCESS", "REGION_LOCKED"], var.serving_locality)
    error_message = "serving_locality must be GLOBAL_ACCESS or REGION_LOCKED."
  }
}
