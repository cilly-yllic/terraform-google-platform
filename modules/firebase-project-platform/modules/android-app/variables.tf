variable "project" {
  description = "GCP project ID."
  type        = string
}

variable "name" {
  description = "Internal reference name (settings.yml の apps[].name)。display_name の fallback。"
  type        = string
}

variable "package_name" {
  description = "Android package name (例: com.example.app)。必須。"
  type        = string

  validation {
    condition     = length(var.package_name) > 0
    error_message = "android app requires package_name."
  }
}

variable "display_name" {
  description = "Firebase Console display name。省略時 var.name 流用。"
  type        = string
  default     = ""
}

variable "sha1_hashes" {
  description = "SHA-1 cert hashes (App Check / Dynamic Links 用、optional)。"
  type        = list(string)
  default     = []
}

variable "sha256_hashes" {
  description = "SHA-256 cert hashes (App Check / Dynamic Links 用、optional)。"
  type        = list(string)
  default     = []
}
