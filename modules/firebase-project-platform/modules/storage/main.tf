# ---------------------------------------------------------------------------
# Default bucket – always created to avoid Firebase side-effects
# ---------------------------------------------------------------------------

resource "google_firebase_storage_bucket" "default" {
  provider  = google-beta
  project   = var.project
  bucket_id = "${var.project}.firebasestorage.app"
}

# ---------------------------------------------------------------------------
# Default bucket – initial rules (deny all)
# ---------------------------------------------------------------------------

resource "google_firebaserules_ruleset" "storage" {
  project = var.project

  source {
    files {
      name    = "storage.rules"
      content = <<-RULES
        rules_version = '2';
        service firebase.storage {
          match /b/{bucket}/o {
            match /{allPaths=**} {
              allow read, write: if false;
            }
          }
        }
      RULES
    }
  }

  depends_on = [google_firebase_storage_bucket.default]
}

resource "google_firebaserules_release" "storage" {
  provider     = google-beta
  project      = var.project
  name         = "firebase.storage/${google_firebase_storage_bucket.default.bucket_id}"
  ruleset_name = "projects/${var.project}/rulesets/${google_firebaserules_ruleset.storage.name}"
}

# ---------------------------------------------------------------------------
# Additional buckets
# ---------------------------------------------------------------------------

locals {
  # for_each キーは 入力 name (state stability のため)。resolved_name は
  # auto_prefix=true の時に `{project}-` で包んだ最終 bucket 名。
  additional_buckets = {
    for b in var.buckets : b.name => {
      resolved_name = b.auto_prefix ? "${var.project}-${b.name}" : b.name
      location      = b.location != "" ? b.location : var.location
      storage_class = b.storage_class != "" ? b.storage_class : "REGIONAL"
      iams          = b.iams
    }
  }

  bucket_iam_bindings = flatten([
    for bname, bval in local.additional_buckets : [
      for iam in bval.iams : {
        key     = "${bname}-${iam.role}"
        bucket  = bname
        role    = iam.role
        members = iam.members
      }
    ]
  ])
}

resource "google_storage_bucket" "additional" {
  for_each                    = local.additional_buckets
  project                     = var.project
  name                        = each.value.resolved_name
  location                    = each.value.location
  storage_class               = each.value.storage_class
  uniform_bucket_level_access = true
}

resource "google_firebase_storage_bucket" "additional" {
  for_each  = local.additional_buckets
  provider  = google-beta
  project   = var.project
  bucket_id = google_storage_bucket.additional[each.key].id
}

resource "google_storage_bucket_iam_binding" "additional" {
  for_each = { for binding in local.bucket_iam_bindings : binding.key => binding }
  bucket   = google_storage_bucket.additional[each.value.bucket].name
  role     = each.value.role
  members  = each.value.members
}

# ---------------------------------------------------------------------------
# Firestore Backup Bucket (optional)
# ---------------------------------------------------------------------------

data "google_project" "this" {
  count      = var.firestore_backup != null ? 1 : 0
  project_id = var.project
}

locals {
  firestore_backup_iam_members = {
    cloud_functions = "${var.project}@appspot.gserviceaccount.com"
    cloud_run       = var.firestore_backup != null ? "${try(data.google_project.this[0].number, "")}-compute@developer.gserviceaccount.com" : ""
  }
}

resource "google_storage_bucket" "firestore_backup" {
  count   = var.firestore_backup != null ? 1 : 0
  project = var.project
  # auto_prefix=true の時のみ `{project}-` を付与 (buckets[] と同じセマンティクス)。
  # count=0 の時は本ブロックは instantiate されないので var.firestore_backup の null 参照は起きない。
  name          = var.firestore_backup.auto_prefix ? "${var.project}-${var.firestore_backup.bucket_name}" : var.firestore_backup.bucket_name
  location      = var.location
  storage_class = "STANDARD"

  autoclass {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7 * 365
    }
  }

  soft_delete_policy {
    retention_duration_seconds = var.firestore_backup.soft_delete_policy.retention_duration_seconds
  }
}

resource "google_firebase_storage_bucket" "firestore_backup" {
  count     = var.firestore_backup != null ? 1 : 0
  provider  = google-beta
  project   = var.project
  bucket_id = google_storage_bucket.firestore_backup[0].id
}

resource "google_project_iam_member" "firestore_export" {
  count   = var.firestore_backup != null ? 1 : 0
  project = var.project
  role    = "roles/datastore.importExportAdmin"
  member  = "serviceAccount:${local.firestore_backup_iam_members[var.firestore_backup.export_platform]}"
}

resource "google_storage_bucket_iam_member" "firestore_backup_admin" {
  count      = var.firestore_backup != null ? 1 : 0
  bucket     = google_storage_bucket.firestore_backup[0].name
  role       = "roles/storage.admin"
  member     = google_project_iam_member.firestore_export[0].member
  depends_on = [google_storage_bucket.firestore_backup, google_project_iam_member.firestore_export]
}
