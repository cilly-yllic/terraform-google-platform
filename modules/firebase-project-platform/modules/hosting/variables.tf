variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "site_id" {
  description = "Firebase Hosting site ID (= subdomain). Globally unique."
  type        = string
}

variable "app_id" {
  description = "Firebase Web App ID to link this hosting site to."
  type        = string
}
