output "name" {
  description = "Internal reference name (passed-through)."
  value       = var.name
}

output "app_id" {
  description = "Firebase Android App auto-generated app ID (1:XXXXX:android:abc…)."
  value       = google_firebase_android_app.this.app_id
}

output "package_name" {
  description = "Android package name."
  value       = google_firebase_android_app.this.package_name
}

output "display_name" {
  description = "Firebase Android App display name."
  value       = google_firebase_android_app.this.display_name
}
