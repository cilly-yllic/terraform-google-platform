output "user_members" {
  description = "IAM members assigned to users."
  value       = [for v in google_project_iam_member.user : v.member]
}

output "user_roles" {
  description = "IAM roles assigned to users."
  value       = [for v in google_project_iam_member.user : v.role]
}

output "ci_service_account_email" {
  description = "CI service account email."
  value       = var.ci_service_account != null ? google_service_account.ci[0].email : null
}

output "ci_service_account_roles" {
  description = "IAM roles assigned to the CI service account."
  value       = var.ci_service_account != null ? var.ci_service_account.roles : []
}

output "ci_service_account_wif_members" {
  description = "WIF principalSet members bound to the CI service account (empty when wif is not configured)."
  value       = [for v in google_service_account_iam_member.ci_wif : v.member]
}

output "service_account_emails" {
  description = "Created service account emails."
  value       = { for k, v in google_service_account.this : k => v.email }
}

output "service_account_ids" {
  description = "Created service account unique IDs."
  value       = { for k, v in google_service_account.this : k => v.unique_id }
}

output "service_account_roles" {
  description = "IAM roles assigned to each service account."
  value       = local.sa_computed_roles
}
