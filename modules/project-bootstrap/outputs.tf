output "project_id" {
  description = "The project ID"
  value       = module.project.project_id
}

output "project_number" {
  description = "The numeric identifier of the project"
  value       = module.project.project_number
}

output "terraform_service_account_id" {
  description = "The Terraform service account ID"
  value       = module.service_account.id
}

output "terraform_service_account_email" {
  description = "The Terraform service account email"
  value       = module.service_account.email
}

output "workload_identity_pool_id" {
  description = "The Workload Identity Pool ID (pass-through for downstream modules)"
  value       = var.workload_identity_pool_id
}

output "workload_identity_provider_id" {
  description = "The Workload Identity Provider ID (pass-through for downstream modules)"
  value       = var.workload_identity_provider_id
}

output "project_iam_members" {
  description = "Map of IAM role to member binding for the Terraform SA"
  value       = module.iam.project_iam_members
}

output "wif_principal" {
  description = "The Workload Identity Federation principal used for the SA binding"
  value       = module.iam.wif_principal
}
