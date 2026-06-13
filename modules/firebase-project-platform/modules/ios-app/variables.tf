variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "name" {
  description = "Internal reference name (settings.yml の apps[].name)。display_name の fallback。"
  type        = string
}

variable "bundle_id" {
  description = "iOS Bundle ID (例: com.example.app)。必須。"
  type        = string

  validation {
    condition     = length(var.bundle_id) > 0
    error_message = "ios app requires bundle_id."
  }
}

variable "display_name" {
  description = "Firebase Console display name。省略時 var.name 流用。"
  type        = string
  default     = ""
}

variable "app_store_id" {
  description = "App Store ID (numeric, optional)。"
  type        = string
  default     = ""
}

variable "team_id" {
  description = "Apple Developer Team ID (optional, App Check 等で使用)。"
  type        = string
  default     = ""
}
