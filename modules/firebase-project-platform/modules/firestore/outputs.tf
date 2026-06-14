output "databases" {
  description = "Map of Firestore databases, keyed by database_id."
  value = {
    for k, v in google_firestore_database.this : k => {
      name     = v.name
      location = v.location_id
      type     = v.type
    }
  }
}
