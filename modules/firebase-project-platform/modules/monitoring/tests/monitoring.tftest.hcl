# modules/monitoring の resource の中身の回帰テスト (mock provider のみ、認証不要)。
#   cd modules/firebase-project-platform/modules/monitoring
#   terraform init -backend=false && terraform test

mock_provider "google" {}
mock_provider "google-beta" {}

variables {
  project        = "example-dev"
  project_number = "123456789012"
}

run "empty_creates_nothing" {
  command = plan

  assert {
    condition = (
      length(google_monitoring_notification_channel.this) == 0 &&
      length(google_logging_metric.this) == 0 &&
      length(google_monitoring_alert_policy.this) == 0 &&
      length(google_pubsub_topic_iam_member.notification_publisher) == 0 &&
      length(google_project_service_identity.monitoring_notification) == 0
    )
    error_message = "何も宣言していないのに resource が作られる"
  }
}

run "channels_and_topic_grants" {
  command = apply

  variables {
    notification_channels = {
      ops    = { type = "email", labels = { email_address = "ops@example.com" } }
      alerts = { type = "pubsub", labels = { topic = "alerts" } }
      # 同じ topic を別の書き方で指す → 付与は 1 つ
      alerts-full = { type = "pubsub", display_name = "Alerts (full path)", labels = { topic = "projects/example-dev/topics/alerts" } }
      other       = { type = "pubsub", labels = { topic = "projects/example-shared/topics/alerts" } }
    }
  }

  assert {
    condition = (
      google_monitoring_notification_channel.this["ops"].type == "email" &&
      google_monitoring_notification_channel.this["ops"].display_name == "ops" &&
      google_monitoring_notification_channel.this["ops"].labels["email_address"] == "ops@example.com"
    )
    error_message = "email の通知先の type / 既定の display_name / labels が違う"
  }

  assert {
    condition = (
      google_monitoring_notification_channel.this["alerts"].labels["topic"] == "projects/example-dev/topics/alerts" &&
      google_monitoring_notification_channel.this["alerts-full"].display_name == "Alerts (full path)" &&
      google_monitoring_notification_channel.this["other"].labels["topic"] == "projects/example-shared/topics/alerts"
    )
    error_message = "pubsub の topic が projects/<id>/topics/<name> にそろっていない"
  }

  assert {
    condition = toset(keys(google_pubsub_topic_iam_member.notification_publisher)) == toset([
      "projects/example-dev/topics/alerts",
      "projects/example-shared/topics/alerts",
    ])
    error_message = "topic への付与が topic ごとに 1 つになっていない"
  }

  assert {
    condition = (
      google_pubsub_topic_iam_member.notification_publisher["projects/example-shared/topics/alerts"].project == "example-shared" &&
      google_pubsub_topic_iam_member.notification_publisher["projects/example-shared/topics/alerts"].topic == "alerts" &&
      google_pubsub_topic_iam_member.notification_publisher["projects/example-dev/topics/alerts"].role == "roles/pubsub.publisher" &&
      google_pubsub_topic_iam_member.notification_publisher["projects/example-dev/topics/alerts"].member == "serviceAccount:service-123456789012@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
    )
    error_message = "topic への付与の project / topic / role / member が違う"
  }

  assert {
    condition     = length(google_project_service_identity.monitoring_notification) == 1 && google_project_service_identity.monitoring_notification[0].service == "monitoring.googleapis.com"
    error_message = "Monitoring の通知用 service agent を作っていない"
  }

  assert {
    condition     = output.notification_service_agent == "service-123456789012@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
    error_message = "output notification_service_agent が違う"
  }
}

run "email_only_skips_service_agent" {
  command = plan

  variables {
    project_number = ""
    notification_channels = {
      ops = { type = "email", labels = { email_address = "ops@example.com" } }
    }
  }

  assert {
    condition     = length(google_project_service_identity.monitoring_notification) == 0 && length(google_pubsub_topic_iam_member.notification_publisher) == 0 && output.notification_service_agent == null
    error_message = "email の通知先だけなのに service agent / topic への付与を作る"
  }
}

run "log_metric_is_delta_int64_counter" {
  command = apply

  variables {
    log_metrics = {
      app-error-events = {
        filter           = "severity>=ERROR"
        description      = "Error log entries"
        label_extractors = { code = "EXTRACT(jsonPayload.code)", service = "EXTRACT(resource.labels.service_name)" }
        labels           = { code = "error code" }
      }
      plain = { filter = "severity>=WARNING" }
    }
  }

  assert {
    condition = (
      google_logging_metric.this["app-error-events"].name == "app-error-events" &&
      google_logging_metric.this["app-error-events"].metric_descriptor[0].metric_kind == "DELTA" &&
      google_logging_metric.this["app-error-events"].metric_descriptor[0].value_type == "INT64" &&
      google_logging_metric.this["app-error-events"].description == "Error log entries"
    )
    error_message = "log-based metric が DELTA / INT64 の counter になっていない"
  }

  assert {
    condition = (
      length(google_logging_metric.this["app-error-events"].metric_descriptor[0].labels) == 2 &&
      one([for l in google_logging_metric.this["app-error-events"].metric_descriptor[0].labels : l.description if l.key == "code"]) == "error code" &&
      google_logging_metric.this["app-error-events"].label_extractors["service"] == "EXTRACT(resource.labels.service_name)"
    )
    error_message = "label_extractors の key ごとに label が宣言されていない (labels の説明が付いていない)"
  }

  assert {
    condition     = length(google_logging_metric.this["plain"].metric_descriptor[0].labels) == 0
    error_message = "label_extractors が無いのに label が宣言されている"
  }

  assert {
    condition     = output.log_metric_types["plain"] == "logging.googleapis.com/user/plain"
    error_message = "output log_metric_types が違う"
  }
}

run "alert_policies" {
  command = apply

  variables {
    notification_channels = {
      ops = { type = "email", labels = { email_address = "ops@example.com" } }
    }
    log_metrics = {
      app-error-events = { filter = "severity>=ERROR" }
    }
    alert_policies = {
      threshold = {
        display_name  = "App errors"
        channels      = ["ops"]
        severity      = "ERROR"
        documentation = "See the runbook."
        conditions = [{
          display_name = "error events > 0"
          threshold = {
            filter               = "metric.type=\"logging.googleapis.com/user/app-error-events\""
            comparison           = "COMPARISON_GT"
            threshold_value      = 0
            duration             = "0s"
            alignment_period     = "300s"
            per_series_aligner   = "ALIGN_SUM"
            cross_series_reducer = "REDUCE_SUM"
            group_by_fields      = ["resource.label.service_name"]
          }
        }]
      }
      log = {
        display_name = "Fatal log"
        channels     = ["ops"]
        conditions = [{
          display_name = "fatal"
          log_match    = { filter = "severity=CRITICAL" }
        }]
      }
      log-custom = {
        display_name            = "Fatal log (hourly)"
        channels                = []
        notification_rate_limit = "3600s"
        auto_close              = "1800s"
        conditions = [{
          display_name = "fatal"
          log_match    = { filter = "severity=CRITICAL", label_extractors = { code = "EXTRACT(jsonPayload.code)" } }
        }]
      }
      threshold-plain = {
        display_name = "No aggregation"
        channels     = []
        conditions = [{
          display_name = "raw"
          threshold = {
            filter          = "metric.type=\"logging.googleapis.com/user/app-error-events\""
            comparison      = "COMPARISON_LT"
            threshold_value = 1
            duration        = "60s"
          }
        }]
      }
      threshold-aligner-none = {
        display_name = "Aligner only"
        channels     = []
        conditions = [{
          display_name = "aligner none"
          threshold = {
            filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
            comparison         = "COMPARISON_GT"
            threshold_value    = 0
            duration           = "0s"
            per_series_aligner = "ALIGN_NONE"
          }
        }]
      }
      absent = {
        display_name = "Heartbeat missing"
        channels     = ["ops"]
        combiner     = "AND"
        auto_close   = "1800s"
        conditions = [{
          display_name = "no heartbeat"
          absent = {
            filter             = "metric.type=\"logging.googleapis.com/user/app-error-events\""
            duration           = "600s"
            alignment_period   = "300s"
            per_series_aligner = "ALIGN_SUM"
          }
        }]
      }
    }
  }

  assert {
    condition = (
      google_monitoring_alert_policy.this["threshold"].combiner == "OR" &&
      google_monitoring_alert_policy.this["threshold"].severity == "ERROR" &&
      google_monitoring_alert_policy.this["threshold"].notification_channels == tolist([google_monitoring_notification_channel.this["ops"].id]) &&
      google_monitoring_alert_policy.this["threshold"].documentation[0].content == "See the runbook." &&
      google_monitoring_alert_policy.this["threshold"].documentation[0].mime_type == "text/markdown"
    )
    error_message = "threshold の policy の combiner / severity / 通知先 / documentation が違う"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.this["threshold"].conditions[0].condition_threshold[0].comparison == "COMPARISON_GT" &&
      google_monitoring_alert_policy.this["threshold"].conditions[0].condition_threshold[0].aggregations[0].per_series_aligner == "ALIGN_SUM" &&
      google_monitoring_alert_policy.this["threshold"].conditions[0].condition_threshold[0].aggregations[0].group_by_fields == tolist(["resource.label.service_name"]) &&
      length(google_monitoring_alert_policy.this["threshold"].alert_strategy) == 0
    )
    error_message = "threshold の condition / aggregations が違う (metric の policy に alert_strategy が付いている)"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.this["log"].conditions[0].condition_matched_log[0].filter == "severity=CRITICAL" &&
      google_monitoring_alert_policy.this["log"].alert_strategy[0].notification_rate_limit[0].period == "300s"
    )
    error_message = "log_match の policy に既定の notification_rate_limit (300s) が付いていない"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.this["log-custom"].alert_strategy[0].notification_rate_limit[0].period == "3600s" &&
      google_monitoring_alert_policy.this["log-custom"].alert_strategy[0].auto_close == "1800s" &&
      google_monitoring_alert_policy.this["log-custom"].conditions[0].condition_matched_log[0].label_extractors["code"] == "EXTRACT(jsonPayload.code)" &&
      length(google_monitoring_alert_policy.this["log-custom"].notification_channels) == 0
    )
    error_message = "log_match の policy の notification_rate_limit / auto_close / label_extractors が違う"
  }

  assert {
    condition = (
      google_monitoring_alert_policy.this["absent"].combiner == "AND" &&
      google_monitoring_alert_policy.this["absent"].conditions[0].condition_absent[0].duration == "600s" &&
      google_monitoring_alert_policy.this["absent"].alert_strategy[0].auto_close == "1800s" &&
      length(google_monitoring_alert_policy.this["absent"].alert_strategy[0].notification_rate_limit) == 0
    )
    error_message = "absent の policy の condition / auto_close が違う (metric の policy に notification_rate_limit が付いている)"
  }

  assert {
    condition     = length(google_monitoring_alert_policy.this["threshold-plain"].conditions[0].condition_threshold[0].aggregations) == 0
    error_message = "集計のフィールドを 1 つも書いていないのに aggregations が付いている"
  }

  assert {
    condition = (
      length(google_monitoring_alert_policy.this["threshold-aligner-none"].conditions[0].condition_threshold[0].aggregations) == 1 &&
      google_monitoring_alert_policy.this["threshold-aligner-none"].conditions[0].condition_threshold[0].aggregations[0].per_series_aligner == "ALIGN_NONE"
    )
    error_message = "alignment_period なしの per_series_aligner が aggregations に入っていない (黙って捨てている)"
  }

  assert {
    condition     = toset(keys(output.alert_policy_names)) == toset(["threshold", "log", "log-custom", "threshold-plain", "threshold-aligner-none", "absent"])
    error_message = "output alert_policy_names に policy が出ていない"
  }
}
