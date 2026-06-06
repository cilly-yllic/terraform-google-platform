# modules/app-hosting

Submodule that creates a Firebase App Hosting backend, plus the compute Service Account / IAM it needs.

<details><summary>Ja</summary>

Firebase App Hosting backend + 必要な compute service account / IAM を作成する submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_service_account.app_hosting` | `google` | Compute SA (`firebase-app-hosting-compute`) — only created when `service_account` is empty |
| `google_project_iam_member.app_hosting_runner` | `google` | Grants `roles/firebaseapphosting.computeRunner` to the compute SA |
| `google_firebase_app_hosting_backend.this` | `google-beta` | App Hosting backend (`{project}-app-hosting`) |

If `service_account` is provided explicitly, SA creation and role-grant are skipped (an existing SA is reused).

<details><summary>Ja</summary>

`service_account` を明示的に指定した場合、SA 作成と role 付与はスキップされる (既存 SA を再利用する)。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Backend location |
| `app_id` | `string` | (required) | Firebase Web App ID (typically passed from the `hosting` submodule) |
| `service_account` | `string` | `""` (= auto-create) | Compute SA email. Empty triggers auto-creation. |
| `serving_locality` | `string` | `"GLOBAL_ACCESS"` | `GLOBAL_ACCESS` / `REGION_LOCKED` |

## Outputs

| Name | Description |
|------|-------------|
| `name` | App Hosting backend resource name |
| `uri` | Backend URI |

## Related APIs

- `firebaseapphosting.googleapis.com`
- `run.googleapis.com`
- `cloudbuild.googleapis.com`
- `artifactregistry.googleapis.com`
- `iam.googleapis.com` (for SA creation)

## Invocation condition

Called when `var.app_hosting != null`.

## Out of scope

- Source repository integration (set via Console)
- App Hosting rollout policy
- Build configuration (`apphosting.yaml`)

<details><summary>Ja</summary>

- ソースリポジトリ連携 (Console 側で設定)
- App Hosting rollout policy
- ビルド設定 (`apphosting.yaml`)

</details>
