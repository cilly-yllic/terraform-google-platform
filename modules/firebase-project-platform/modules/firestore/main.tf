# ---------------------------------------------------------------------------
# Firestore Databases (multiple)
#
# 各 entry は database_id をキーに for_each で展開。(default) も他の DB と同列。
# location 省略時は var.default_location に fallback (= parent で var.region)。
# ---------------------------------------------------------------------------

locals {
  databases_map = {
    for db in var.databases : db.database_id => {
      location                = db.location != "" ? db.location : var.default_location
      type                    = db.type
      delete_protection_state = db.delete_protection_state
      point_in_time_recovery  = db.point_in_time_recovery
    }
  }
}

resource "google_firestore_database" "this" {
  for_each                          = local.databases_map
  project                           = var.project
  name                              = each.key
  location_id                       = each.value.location
  type                              = each.value.type
  delete_protection_state           = each.value.delete_protection_state
  point_in_time_recovery_enablement = each.value.point_in_time_recovery ? "POINT_IN_TIME_RECOVERY_ENABLED" : "POINT_IN_TIME_RECOVERY_DISABLED"
}

# ---------------------------------------------------------------------------
# 初期 deny-all rules (project-level)。Firebase の `cloud.firestore` service
# に対する ruleset / release は全 Firestore database に適用される。
# ---------------------------------------------------------------------------

resource "google_firebaserules_ruleset" "default" {
  count   = var.apply_default_rules && length(var.databases) > 0 ? 1 : 0
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

  depends_on = [google_firestore_database.this]
}

resource "google_firebaserules_release" "default" {
  count        = var.apply_default_rules && length(var.databases) > 0 ? 1 : 0
  project      = var.project
  name         = "cloud.firestore"
  ruleset_name = "projects/${var.project}/rulesets/${google_firebaserules_ruleset.default[0].name}"
}
