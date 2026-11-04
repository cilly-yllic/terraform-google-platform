output "notification_channel_ids" {
  description = "Notification channel IDs (projects/<project>/notificationChannels/<id>), keyed by channel name."
  value       = { for k, c in google_monitoring_notification_channel.this : k => c.id }
}

output "alert_policy_names" {
  description = "Alert policy resource names (projects/<project>/alertPolicies/<id>), keyed by policy name."
  value       = { for k, p in google_monitoring_alert_policy.this : k => p.name }
}

output "log_metric_types" {
  description = "Metric types of the log-based metrics (logging.googleapis.com/user/<name>), keyed by metric name."
  value       = { for k, m in google_logging_metric.this : k => "logging.googleapis.com/user/${m.name}" }
}

output "notification_service_agent" {
  description = "Email of the Monitoring notification service agent granted roles/pubsub.publisher on the pubsub topics (null when no pubsub channel)."
  value       = local.notification_service_agent
}
