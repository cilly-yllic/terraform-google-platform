# modules/cloud-tasks

Placeholder submodule for enabling the Cloud Tasks API.

<details><summary>Ja</summary>

Cloud Tasks API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. Queues (`google_cloud_tasks_queue`) are not created by this module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Cloud Tasks location (root module passes `var.region` or `cloud_tasks.location`) |

## Outputs

| Name | Description |
|------|-------------|
| `enabled` | Always `true` (constant marker that Cloud Tasks is enabled) |

## Related APIs

- `cloudtasks.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.cloud_tasks != null`.

## Design intent

Queues are typically created per-service or per-purpose from separate Terraform stacks / SAs, so this module limits itself to API enablement. Kept as an expansion point if queue management via this module becomes desirable.

<details><summary>Ja</summary>

queue は service 単位 / 用途単位で別 Terraform stack や Service Account から作成するケースが多いため、本モジュールでは API 有効化のみに留めている。queue を本モジュール経由で管理したくなった場合の拡張ポイントとして残している。

</details>
