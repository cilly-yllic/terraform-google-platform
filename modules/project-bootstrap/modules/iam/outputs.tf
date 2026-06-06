output "project_iam_members" {
  description = "Map of IAM role to member binding"
  value       = { for role, member in google_project_iam_member.terraform_sa : role => member.member }
}

output "wif_principal" {
  description = "The Workload Identity Federation principal"
  value       = local.wif_principal
}
