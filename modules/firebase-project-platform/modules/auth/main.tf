resource "google_identity_platform_config" "this" {
  provider = google-beta
  project  = var.project

  dynamic "blocking_functions" {
    for_each = (var.blocking_functions.before_create != "" || var.blocking_functions.before_sign_in != "") ? [1] : []
    content {
      dynamic "triggers" {
        for_each = var.blocking_functions.before_create != "" ? [var.blocking_functions.before_create] : []
        content {
          event_type   = "beforeCreate"
          function_uri = triggers.value
        }
      }
      dynamic "triggers" {
        for_each = var.blocking_functions.before_sign_in != "" ? [var.blocking_functions.before_sign_in] : []
        content {
          event_type   = "beforeSignIn"
          function_uri = triggers.value
        }
      }
    }
  }
}
