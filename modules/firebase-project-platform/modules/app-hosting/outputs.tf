output "name" {
  description = "App Hosting backend resource name."
  value       = google_firebase_app_hosting_backend.this.name
}

output "uri" {
  description = "App Hosting backend URI."
  value       = google_firebase_app_hosting_backend.this.uri
}
