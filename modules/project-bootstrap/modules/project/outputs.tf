output "project_id" {
  description = "The project ID"
  value       = google_project.this.project_id
}

output "project_number" {
  description = "The numeric identifier of the project"
  value       = google_project.this.number
}
