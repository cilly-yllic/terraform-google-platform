output "default_bucket" {
  description = "Firebase default Storage bucket name (null when default_bucket=false)."
  value       = one(google_firebase_storage_bucket.default[*].bucket_id)
}

output "additional_buckets" {
  description = "Additional bucket names (key = input name, value = resolved GCS name)."
  value       = { for k, v in google_storage_bucket.additional : k => v.name }
}

output "firestore_backup_bucket" {
  description = "Firestore backup bucket name."
  value       = var.firestore_backup != null ? google_storage_bucket.firestore_backup[0].name : null
}
