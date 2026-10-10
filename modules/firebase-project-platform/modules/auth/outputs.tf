locals {
  config = one(concat(
    google_identity_platform_config.this,
    google_identity_platform_config.deploy_managed,
  ))
}

output "name" {
  description = "Identity Platform config resource name."
  value       = local.config.name
}

output "authorized_domains" {
  description = "Effective OAuth authorized domains (computed by the provider when not managed)."
  value       = local.config.authorized_domains
}
