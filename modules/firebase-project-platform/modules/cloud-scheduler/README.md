# modules/cloud-scheduler

Placeholder submodule for enabling the Cloud Scheduler API.

<details><summary>Ja</summary>

Cloud Scheduler API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. Jobs (`google_cloud_scheduler_job`) are not created by this module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Cloud Scheduler location |

## Outputs

| Name | Description |
|------|-------------|
| `enabled` | Always `true` (constant marker that Cloud Scheduler is enabled) |

## Related APIs

- `cloudscheduler.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.cloud_scheduler != null`.

## Design intent

Scheduled jobs are tied to service-specific business logic and are usually managed in separate Terraform stacks. This module limits itself to API enablement.

<details><summary>Ja</summary>

定期実行 job は service 側のドメインロジックに紐づくため、別 Terraform stack で管理されることが多い。本モジュールでは API 有効化のみ。

</details>
