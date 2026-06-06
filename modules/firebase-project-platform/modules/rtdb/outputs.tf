output "name" {
  description = "Realtime Database instance resource name."
  value       = google_firebase_database_instance.this.name
}

output "database_url" {
  description = "Realtime Database URL."
  value       = google_firebase_database_instance.this.database_url
}
