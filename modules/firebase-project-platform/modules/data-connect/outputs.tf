output "name" {
  description = "Data Connect service resource name."
  value       = google_firebase_data_connect_service.this.name
}

output "cloud_sql_instance_name" {
  description = "Cloud SQL instance name."
  value       = var.cloud_sql != null ? google_sql_database_instance.this[0].name : null
}

output "cloud_sql_connection_name" {
  description = "Cloud SQL instance connection name."
  value       = var.cloud_sql != null ? google_sql_database_instance.this[0].connection_name : null
}

output "cloud_sql_database" {
  description = "Cloud SQL database name."
  value       = var.cloud_sql != null ? google_sql_database.this[0].name : null
}
