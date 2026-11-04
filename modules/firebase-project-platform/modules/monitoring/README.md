# modules/monitoring

Submodule that creates **Cloud Monitoring notification channels, log-based metrics and alert policies** from the root variable `monitoring`.

<details><summary>Ja</summary>

ルートの変数 `monitoring` から、**Cloud Monitoring の通知先・log-based metric・alert policy** を作る submodule。

</details>

## Resources created

| Resource | Role |
|----------|------|
| `google_monitoring_notification_channel.this["<name>"]` | One per `notification_channels` entry (`email` / `pubsub`) |
| `google_project_service_identity.monitoring_notification` | (pubsub channels only, `google-beta`) Makes sure the Monitoring notification service agent `service-<number>@gcp-sa-monitoring-notification.iam.gserviceaccount.com` exists |
| `google_pubsub_topic_iam_member.notification_publisher["projects/<id>/topics/<name>"]` | (pubsub channels only) `roles/pubsub.publisher` for the service agent, on each distinct topic |
| `google_logging_metric.this["<metric name>"]` | One log-based counter (`DELTA` / `INT64`) per `log_metrics` entry. One `STRING` label per `label_extractors` key |
| `google_monitoring_alert_policy.this["<name>"]` | One per `alert_policies` entry (`log_match` → `condition_matched_log`, `threshold` → `condition_threshold`, `absent` → `condition_absent`) |

Pub/Sub topics are **not** created here. A topic given by name is resolved to `projects/<project>/topics/<name>`; a full path may point to a topic in another project (the caller then needs permission to set IAM on it).

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `project_number` | `string` | `""` | Project number, for the notification service agent. Required when a pubsub channel is declared |
| `notification_channels` | `map(object)` | `{}` | See [variables-reference.md](../../../../docs/firebase-project-platform/variables-reference.md#monitoring) |
| `log_metrics` | `map(object)` | `{}` | 〃 |
| `alert_policies` | `map(object)` | `{}` | 〃 |

The root module validates the shape (`var.monitoring`); this submodule only applies it.

## Outputs

| Name | Description |
|------|-------------|
| `notification_channel_ids` | `{ <name> = "projects/<project>/notificationChannels/<id>" }` |
| `alert_policy_names` | `{ <name> = "projects/<project>/alertPolicies/<id>" }` |
| `log_metric_types` | `{ <metric name> = "logging.googleapis.com/user/<metric name>" }` |
| `notification_service_agent` | Email of the notification service agent (`null` without pubsub channels) |

## Related APIs

- `monitoring.googleapis.com`, `logging.googleapis.com` (auto-enabled by the root module when `monitoring` declares anything)
- `pubsub.googleapis.com` (auto-enabled when a pubsub channel is declared)

## Invocation condition

Called when `monitoring` has at least one entry in `notification_channels`, `log_metrics` or `alert_policies`.

## Ordering

- Channels are created after the topic grants, so the first notification can be published.
- Alert policies are created after the log-based metrics, so a filter may reference `logging.googleapis.com/user/<metric name>` of a metric declared in the same `monitoring`.
- `alert_strategy.notification_rate_limit` is set only on policies with a `log_match` condition (GCP requires it there; default `300s`).

<details><summary>Ja</summary>

- topic への付与の後に channel を作る (最初の通知から publish できるように)。
- log-based metric の後に alert policy を作る。同じ `monitoring` の metric (`logging.googleapis.com/user/<metric name>`) を filter で参照できる。
- `alert_strategy.notification_rate_limit` は `log_match` の policy にだけ付ける (GCP がそこで必須にする。既定 `300s`)。
- Pub/Sub の topic はここでは作らない。名前だけなら `projects/<project>/topics/<name>` にそろえる。フルパスなら別の project の topic も指せる (その topic の IAM を変える権限が要る)。

</details>
