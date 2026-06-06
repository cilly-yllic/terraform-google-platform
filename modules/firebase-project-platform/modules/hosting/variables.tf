variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "site_id" {
  description = "Firebase Hosting site ID. If empty, defaults to project ID."
  type        = string
  default     = ""
}
