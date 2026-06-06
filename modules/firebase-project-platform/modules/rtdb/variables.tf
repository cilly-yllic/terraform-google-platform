variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "location" {
  description = "Realtime Database instance location."
  type        = string
}

variable "type" {
  description = "Realtime Database instance type."
  type        = string
  default     = "DEFAULT_DATABASE"

  validation {
    condition     = contains(["DEFAULT_DATABASE", "USER_DATABASE"], var.type)
    error_message = "type must be DEFAULT_DATABASE or USER_DATABASE."
  }
}
