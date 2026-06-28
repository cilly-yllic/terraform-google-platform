output "name" {
  description = "App Hosting backend resource name."
  value       = google_firebase_app_hosting_backend.this.name
}

output "uri" {
  description = "App Hosting backend URI."
  value       = google_firebase_app_hosting_backend.this.uri
}

# 各 custom domain について、別レイヤで登録すべき DNS レコード
# (所有権確認 TXT + serving 用) を含む。DNS を手動/別管理する運用向け。
output "custom_domains" {
  description = "Map of registered custom domains, keyed by domain. Each value contains required_dns_updates for the external DNS layer."
  value = {
    for domain, d in google_firebase_app_hosting_domain.this : domain => {
      required_dns_updates = d.required_dns_updates
    }
  }
}
