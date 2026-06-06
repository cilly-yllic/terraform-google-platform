output "id" {
  description = "The service account ID"
  value       = google_service_account.this.account_id
}

output "email" {
  description = "The service account email"
  value       = google_service_account.this.email
}

output "name" {
  description = "The fully-qualified name of the service account"
  value       = google_service_account.this.name
}
