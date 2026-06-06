output "site_id" {
  description = "Firebase Hosting site ID."
  value       = google_firebase_hosting_site.this.site_id
}

output "app_id" {
  description = "Firebase Web App ID."
  value       = google_firebase_web_app.this.app_id
}

output "default_url" {
  description = "Firebase Hosting default URL."
  value       = google_firebase_hosting_site.this.default_url
}
