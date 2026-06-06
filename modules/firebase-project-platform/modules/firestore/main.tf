# ---------------------------------------------------------------------------
# Default database – always created
# ---------------------------------------------------------------------------

resource "google_firestore_database" "default" {
  project                           = var.project
  name                              = "(default)"
  location_id                       = var.location
  type                              = var.type
  delete_protection_state           = var.delete_protection_state
  point_in_time_recovery_enablement = var.point_in_time_recovery ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
}

# ---------------------------------------------------------------------------
# Default database – initial rules (deny all)
# ---------------------------------------------------------------------------

resource "google_firebaserules_ruleset" "default" {
  project = var.project

  source {
    files {
      name    = "firestore.rules"
      content = <<-RULES
        rules_version = '2';
        service cloud.firestore {
          match /databases/{database}/documents {
            match /{document=**} {
              allow read, write: if false;
            }
          }
        }
      RULES
    }
  }

  depends_on = [google_firestore_database.default]
}

resource "google_firebaserules_release" "default" {
  project      = var.project
  name         = "cloud.firestore"
  ruleset_name = "projects/${var.project}/rulesets/${google_firebaserules_ruleset.default.name}"
}

# ---------------------------------------------------------------------------
# Additional databases
# ---------------------------------------------------------------------------

resource "google_firestore_database" "additional" {
  for_each                          = { for db in var.databases : db.database_id => db }
  project                           = var.project
  name                              = each.value.database_id
  location_id                       = each.value.location != "" ? each.value.location : var.location
  type                              = each.value.type
  delete_protection_state           = each.value.delete_protection_state
  point_in_time_recovery_enablement = each.value.point_in_time_recovery ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
}
