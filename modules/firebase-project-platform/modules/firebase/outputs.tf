output "project_id" {
  description = "Firebase project ID."
  value       = google_firebase_project.this.project
}

output "display_name" {
  description = "Firebase project display name."
  value       = google_firebase_project.this.display_name
}
