variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "project_name" {
  description = "GCP Project display name"
  type        = string
}

variable "billing_account_id" {
  description = "Billing Account ID to associate with the project"
  type        = string
}

variable "labels" {
  description = "Labels to apply to the project"
  type        = map(string)
  default     = {}
}

variable "org_id" {
  description = "The numeric ID of the organization to create the project under"
  type        = string
  default     = null
}

variable "folder_id" {
  description = "The numeric ID of the folder to create the project under"
  type        = string
  default     = null
}

variable "deletion_policy" {
  description = "The deletion policy for the project. PREVENT, ABANDON, or DELETE."
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy must be one of: PREVENT, ABANDON, DELETE."
  }
}
