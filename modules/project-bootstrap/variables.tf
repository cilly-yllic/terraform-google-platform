variable "project_id" {
  description = "GCP Project ID to create"
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

variable "terraform_service_account_id" {
  description = "Terraform Service Account ID (e.g. terraform-example-prd)"
  type        = string
}

variable "tfc_workspace_name" {
  description = "Terraform Cloud Workspace name for direct WIF impersonation"
  type        = string
}

variable "labels" {
  description = "Labels to apply to the project"
  type        = map(string)
  default     = {}
}

variable "bootstrap_project_id" {
  description = "The project ID of the infra-bootstrap project where the SA is created"
  type        = string
  default     = "infra-bootstrap"
}

variable "workload_identity_pool_id" {
  description = "Workload Identity Pool ID"
  type        = string
  default     = "terraform-cloud"
}

variable "workload_identity_provider_id" {
  description = "Workload Identity Provider ID. Passed through as output for downstream modules (WIF principalSet uses pool ID only)."
  type        = string
  default     = "terraform-cloud"
}

variable "org_id" {
  description = "The numeric ID of the organization to create the project under. At least one of org_id or folder_id must be specified. If folder_id is set, org_id is ignored."
  type        = string
  default     = null
}

variable "folder_id" {
  description = "The numeric ID of the folder to create the project under. Takes precedence over org_id if both are set."
  type        = string
  default     = null
}

variable "deletion_policy" {
  description = "The deletion policy for the project. PREVENT (default), ABANDON, or DELETE."
  type        = string
  default     = "PREVENT"

  validation {
    condition     = contains(["PREVENT", "ABANDON", "DELETE"], var.deletion_policy)
    error_message = "deletion_policy must be one of: PREVENT, ABANDON, DELETE."
  }
}
