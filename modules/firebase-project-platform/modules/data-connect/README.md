# modules/data-connect

Submodule that creates Firebase Data Connect **services (one per `services[]` entry)**, each backed by a Cloud SQL instance + database. Multiple services that share the same `cloud_sql.instance_id` are **deduplicated** into a single Cloud SQL instance.

<details><summary>Ja</summary>

`services[]` の各 entry ごとに Firebase Data Connect service を作成し、それぞれ Cloud SQL instance + database を backend にする submodule。同じ `cloud_sql.instance_id` を共有する service は **dedup** されて 1 つの Cloud SQL instance に集約される。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_data_connect_service.this` | `google-beta` | Data Connect services (`for_each` over `services[]`, keyed by `service_id`) |
| `google_sql_database_instance.this` | `google` | Cloud SQL instances (`for_each`, keyed by `instance_id`, deduplicated) |
| `google_sql_database.this` | `google` | Cloud SQL databases (`for_each`, keyed by `{instance_id}/{database}`) |
| `terraform_data.validate_cloud_sql_instance_consistency` | — | Plan-time precondition: services sharing an `instance_id` must agree on `tier` / `database_version` / `deletion_protection` / `location` |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `default_location` | `string` | (required) | Fallback location used when a `services[]` entry omits `location` |
| `services` | `list(object)` | `[]` | Data Connect services (see fields below) |

Fields of each `services[]` entry:

| Field | Default | Description |
|-------|---------|-------------|
| `service_id` | (required) | Data Connect service ID (project-unique) |
| `location` | `var.default_location` | Service location |
| `cloud_sql.instance_id` | (required) | Cloud SQL instance name (shared `instance_id` deduplicates) |
| `cloud_sql.database` | (required) | Logical database name inside the instance |
| `cloud_sql.tier` | `"db-f1-micro"` | machine tier (must match across shared instance) |
| `cloud_sql.database_version` | `"POSTGRES_15"` | PostgreSQL version (must match across shared instance) |
| `cloud_sql.deletion_protection` | `false` | Instance delete protection (must match across shared instance) |
| `cloud_sql.location` | service `location` | Cloud SQL region (must match across shared instance) |

## Outputs

| Name | Description |
|------|-------------|
| `services` | Map keyed by `service_id`. Each value contains `resource_name`, `location`. |
| `cloud_sql_instances` | Map keyed by `instance_id` (deduplicated). Each value contains `name`, `connection_name`, `region`, `database_version`. |
| `cloud_sql_databases` | Map keyed by `{instance_id}/{database}`. Each value contains `instance`, `name`. |

## Related APIs

- `firebasedataconnect.googleapis.com`
- `sqladmin.googleapis.com`
- `cloudbilling.googleapis.com` (the Firebase CLI checks billing during Data Connect deploys)

## Invocation condition

Called when `var.data_connect != null`.
