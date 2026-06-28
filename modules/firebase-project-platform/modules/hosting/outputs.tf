output "site_id" {
  description = "Firebase Hosting site ID."
  value       = google_firebase_hosting_site.this.site_id
}

output "app_id" {
  description = "Linked Firebase Web App ID."
  value       = google_firebase_hosting_site.this.app_id
}

output "default_url" {
  description = "Firebase Hosting default URL."
  value       = google_firebase_hosting_site.this.default_url
}

# 各 custom domain について、別レイヤで登録すべき DNS レコード
# (所有権確認 + serving 用) を含む。DNS を手動/別管理する運用向け。
output "custom_domains" {
  description = "Map of registered custom domains, keyed by domain. Each value contains required_dns_updates for the external DNS layer."
  value = {
    for domain, cd in google_firebase_hosting_custom_domain.this : domain => {
      required_dns_updates = cd.required_dns_updates
    }
  }
}
