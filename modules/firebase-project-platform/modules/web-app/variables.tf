variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "name" {
  description = "Internal reference name. Used as fallback for display_name when not specified."
  type        = string
}

variable "display_name" {
  description = "Firebase Console display name. Defaults to var.name when empty."
  type        = string
  default     = ""
}
