output "name" {
  description = "App Hosting backend resource name."
  value       = google_firebase_app_hosting_backend.this.name
}

output "uri" {
  description = "App Hosting backend URI."
  value       = google_firebase_app_hosting_backend.this.uri
}

# 各 custom domain の状態。custom_domain_status は cert/host/ownership state と
# **required_dns_updates を nested で**含む (App Hosting の domain リソースは
# hosting (classic) と違い top-level required_dns_updates を持たないため、
# custom_domain_status をそのまま公開する)。DNS を手動/別管理する運用向け。
output "custom_domains" {
  description = "Map of registered custom domains, keyed by domain. Each value contains custom_domain_status (cert/host/ownership state + nested required_dns_updates) for the external DNS layer."
  value = {
    for domain, d in google_firebase_app_hosting_domain.this : domain => {
      custom_domain_status = d.custom_domain_status
    }
  }
}
