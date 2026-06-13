output "name" {
  description = "Internal reference name (passed-through)."
  value       = var.name
}

output "app_id" {
  description = "Firebase Apple App auto-generated app ID (1:XXXXX:ios:abc…)."
  value       = google_firebase_apple_app.this.app_id
}

output "bundle_id" {
  description = "iOS Bundle ID."
  value       = google_firebase_apple_app.this.bundle_id
}

output "display_name" {
  description = "Firebase Apple App display name."
  value       = google_firebase_apple_app.this.display_name
}
