output "name" {
  description = "Identity Platform config resource name."
  value       = google_identity_platform_config.this.name
}

output "authorized_domains" {
  description = "Effective OAuth authorized domains (computed by the provider when not managed)."
  value       = google_identity_platform_config.this.authorized_domains
}
