output "default_database_name" {
  description = "Default Firestore database resource name."
  value       = google_firestore_database.default.name
}

output "default_database_location" {
  description = "Default Firestore database location."
  value       = google_firestore_database.default.location_id
}

output "additional_databases" {
  description = "Additional Firestore database names."
  value       = { for k, v in google_firestore_database.additional : k => v.name }
}
