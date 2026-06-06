variable "project_id" {
  description = "The target GCP project ID for IAM bindings"
  type        = string
}

variable "service_account_email" {
  description = "The email of the Terraform service account"
  type        = string
}

variable "service_account_name" {
  description = "The fully-qualified name of the service account (projects/{project}/serviceAccounts/{email})"
  type        = string
}

variable "bootstrap_project_number" {
  description = "The numeric project number of the bootstrap project"
  type        = string
}

variable "workload_identity_pool_id" {
  description = "The Workload Identity Pool ID"
  type        = string
}

variable "tfc_workspace_name" {
  description = "Terraform Cloud Workspace name for WIF binding"
  type        = string
}
