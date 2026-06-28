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

variable "custom_domains" {
  description = "Custom domains to register for this hosting site (複数可)。空 list なら作らない。DNS 登録は別レイヤ前提 (wait_dns_verification=false)。"
  type        = list(string)
  default     = []
}
