# modules/rtdb

Submodule that creates a Firebase Realtime Database instance.

<details><summary>Ja</summary>

Firebase Realtime Database instance を作成する submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_database_instance.this` | `google-beta` | RTDB instance (`{project}-default-rtdb`) |

The instance ID is fixed at `{project}-default-rtdb` (not currently customizable).

<details><summary>Ja</summary>

instance ID は `{project}-default-rtdb` 固定 (現状カスタマイズ不可)。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | RTDB location (`us-central1`, `asia-southeast1`, etc.) |
| `type` | `string` | `"DEFAULT_DATABASE"` | `DEFAULT_DATABASE` / `USER_DATABASE` |

## Outputs

| Name | Description |
|------|-------------|
| `name` | RTDB instance resource name |
| `database_url` | RTDB HTTPS URL |

## Related APIs

- `firebasedatabase.googleapis.com`

## Invocation condition

Called when `var.rtdb != null`.
