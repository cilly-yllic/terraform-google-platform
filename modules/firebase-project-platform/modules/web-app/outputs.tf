output "name" {
  description = "Internal reference name (passed-through var.name)."
  value       = var.name
}

output "app_id" {
  description = "Firebase Web App auto-generated app ID."
  value       = google_firebase_web_app.this.app_id
}

output "display_name" {
  description = "Firebase Web App display name."
  value       = google_firebase_web_app.this.display_name
}
