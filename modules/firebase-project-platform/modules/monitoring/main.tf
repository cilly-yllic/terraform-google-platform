# ---------------------------------------------------------------------------
# Cloud Monitoring: notification channels, log-based metrics and alert policies.
#
# 何も宣言しなければ何も作らない (ルートは var.monitoring が空なら module 自体を呼ばない)。
# Pub/Sub の topic はこのモジュールでは作らない。宣言された topic に、Monitoring の通知用
# service agent が publish できる role だけを topic 単位で付ける。
# ---------------------------------------------------------------------------

locals {
  # pubsub channel の topic を "projects/<project>/topics/<name>" にそろえる (名前だけなら同じ project)。
  channel_topics = {
    for k, c in var.notification_channels : k => (
      startswith(c.labels.topic, "projects/") ? c.labels.topic : "projects/${var.project}/topics/${c.labels.topic}"
    ) if c.type == "pubsub"
  }

  # 同じ topic を複数の channel が使っても付与は 1 つ。
  notification_topics = toset(values(local.channel_topics))

  notification_service_agent = length(local.notification_topics) > 0 ? (
    "service-${var.project_number}@gcp-sa-monitoring-notification.iam.gserviceaccount.com"
  ) : null

  # alert_strategy.notification_rate_limit は log_match の policy にだけ要る (GCP が必須にする)。
  log_match_policies = toset([
    for k, p in var.alert_policies : k if anytrue([for c in p.conditions : c.log_match != null])
  ])
}

# Monitoring の通知用 service agent (service-<number>@gcp-sa-monitoring-notification) を確実に存在させる。
# 最初の channel を作るまで存在しないことがあり、topic への付与が "does not exist" で失敗するため。
resource "google_project_service_identity" "monitoring_notification" {
  count    = length(local.notification_topics) > 0 ? 1 : 0
  provider = google-beta
  project  = var.project
  service  = "monitoring.googleapis.com"
}

resource "google_pubsub_topic_iam_member" "notification_publisher" {
  for_each = local.notification_topics
  project  = split("/", each.value)[1]
  topic    = split("/", each.value)[3]
  role     = "roles/pubsub.publisher"
  member   = "serviceAccount:${local.notification_service_agent}"

  lifecycle {
    precondition {
      condition     = var.project_number != ""
      error_message = "monitoring: project_number is required for pubsub notification channels."
    }
  }

  depends_on = [google_project_service_identity.monitoring_notification]
}

resource "google_monitoring_notification_channel" "this" {
  for_each     = var.notification_channels
  project      = var.project
  type         = each.value.type
  display_name = coalesce(each.value.display_name, each.key)
  labels = each.value.type == "pubsub" ? merge(each.value.labels, {
    topic = local.channel_topics[each.key]
  }) : each.value.labels

  # 通知が最初から届くよう、topic への付与の後に作る。
  depends_on = [google_pubsub_topic_iam_member.notification_publisher]
}

resource "google_logging_metric" "this" {
  for_each    = var.log_metrics
  project     = var.project
  name        = each.key
  filter      = each.value.filter
  description = each.value.description

  label_extractors = length(each.value.label_extractors) > 0 ? each.value.label_extractors : null

  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    unit        = "1"

    # label_extractors の key ごとに label を宣言する (GCP が対応を必須にする)。labels は説明を足す。
    dynamic "labels" {
      for_each = toset(keys(each.value.label_extractors))
      content {
        key         = labels.value
        value_type  = "STRING"
        description = lookup(each.value.labels, labels.value, null)
      }
    }
  }
}

resource "google_monitoring_alert_policy" "this" {
  for_each     = var.alert_policies
  project      = var.project
  display_name = each.value.display_name
  combiner     = each.value.combiner
  severity     = each.value.severity

  notification_channels = [
    for ch in each.value.channels : google_monitoring_notification_channel.this[ch].id
  ]

  dynamic "documentation" {
    for_each = each.value.documentation == null ? [] : [each.value.documentation]
    content {
      content   = documentation.value
      mime_type = "text/markdown"
    }
  }

  dynamic "conditions" {
    for_each = each.value.conditions
    content {
      display_name = conditions.value.display_name

      dynamic "condition_matched_log" {
        for_each = conditions.value.log_match == null ? [] : [conditions.value.log_match]
        content {
          filter           = condition_matched_log.value.filter
          label_extractors = length(condition_matched_log.value.label_extractors) > 0 ? condition_matched_log.value.label_extractors : null
        }
      }

      dynamic "condition_threshold" {
        for_each = conditions.value.threshold == null ? [] : [conditions.value.threshold]
        content {
          filter          = condition_threshold.value.filter
          comparison      = condition_threshold.value.comparison
          threshold_value = condition_threshold.value.threshold_value
          duration        = condition_threshold.value.duration

          dynamic "aggregations" {
            for_each = (
              condition_threshold.value.alignment_period != null ||
              condition_threshold.value.per_series_aligner != null ||
              condition_threshold.value.cross_series_reducer != null ||
              length(condition_threshold.value.group_by_fields) > 0
            ) ? [condition_threshold.value] : []
            content {
              alignment_period     = aggregations.value.alignment_period
              per_series_aligner   = aggregations.value.per_series_aligner
              cross_series_reducer = aggregations.value.cross_series_reducer
              group_by_fields      = length(aggregations.value.group_by_fields) > 0 ? aggregations.value.group_by_fields : null
            }
          }
        }
      }

      dynamic "condition_absent" {
        for_each = conditions.value.absent == null ? [] : [conditions.value.absent]
        content {
          filter   = condition_absent.value.filter
          duration = condition_absent.value.duration

          dynamic "aggregations" {
            for_each = (
              condition_absent.value.alignment_period != null ||
              condition_absent.value.per_series_aligner != null ||
              condition_absent.value.cross_series_reducer != null ||
              length(condition_absent.value.group_by_fields) > 0
            ) ? [condition_absent.value] : []
            content {
              alignment_period     = aggregations.value.alignment_period
              per_series_aligner   = aggregations.value.per_series_aligner
              cross_series_reducer = aggregations.value.cross_series_reducer
              group_by_fields      = length(aggregations.value.group_by_fields) > 0 ? aggregations.value.group_by_fields : null
            }
          }
        }
      }
    }
  }

  dynamic "alert_strategy" {
    for_each = contains(local.log_match_policies, each.key) || each.value.auto_close != null ? [each.value] : []
    content {
      auto_close = alert_strategy.value.auto_close

      dynamic "notification_rate_limit" {
        for_each = contains(local.log_match_policies, each.key) ? [coalesce(alert_strategy.value.notification_rate_limit, "300s")] : []
        content {
          period = notification_rate_limit.value
        }
      }
    }
  }

  # filter が参照する log-based metric を先に作る。
  depends_on = [google_logging_metric.this]
}
