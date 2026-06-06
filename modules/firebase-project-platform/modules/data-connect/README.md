# modules/data-connect

Submodule that creates a Firebase Data Connect service and, optionally, a Cloud SQL instance + database.

<details><summary>Ja</summary>

Firebase Data Connect service と、任意で Cloud SQL instance / database を作成する submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_data_connect_service.this` | `google-beta` | Data Connect service |
| `google_sql_database_instance.this` | `google` | (optional) Cloud SQL instance (only when `cloud_sql != null`) |
| `google_sql_database.this` | `google` | (optional) Cloud SQL database |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Data Connect / Cloud SQL location |
| `service_id` | `string` | `"{project}-dataconnect"` (empty falls back) | Data Connect service ID |
| `cloud_sql` | `object \| null` | `null` | Cloud SQL config. `null` skips SQL resources. |

Fields of `cloud_sql`:

| Field | Default | Description |
|-------|---------|-------------|
| `instance_id` | `"{project}-fdc"` | Cloud SQL instance name |
| `database` | `project` | database name |
| `tier` | `"db-f1-micro"` | machine tier |
| `database_version` | `"POSTGRES_15"` | PostgreSQL version |
| `deletion_protection` | `false` | Instance delete protection |

## Outputs

| Name | Description |
|------|-------------|
| `name` | Data Connect service resource name |
| `cloud_sql_instance_name` | Cloud SQL instance name (`null` if not created) |
| `cloud_sql_connection_name` | Cloud SQL connection name |
| `cloud_sql_database` | database name |

## Related APIs

- `firebasedataconnect.googleapis.com`
- `sqladmin.googleapis.com`

## Invocation condition

Called when `var.data_connect != null`.
