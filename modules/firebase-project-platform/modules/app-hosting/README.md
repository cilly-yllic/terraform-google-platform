# modules/app-hosting

Submodule that creates a single **bare** Firebase App Hosting backend.

The submodule itself creates only the backend resource. The shared compute Service Account (`firebase-app-hosting-compute`) and its `roles/firebaseapphosting.computeRunner` binding are created **in the root `main.tf`** (once per project, shared across all backends that need it) and the resolved SA email is passed in via `service_account`.

<details><summary>Ja</summary>

単一の **bare** な Firebase App Hosting backend を作成する submodule。

submodule は backend リソースのみを作る。共有 compute Service Account (`firebase-app-hosting-compute`) と `roles/firebaseapphosting.computeRunner` の付与は **ルートの `main.tf`** で行われ (project 単位で 1 つ、必要な全 backend で共有)、解決済みの SA email が `service_account` 経由で渡される。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_app_hosting_backend.this` | `google-beta` | App Hosting backend (named by `backend_id`) |
| `google_firebase_app_hosting_domain.this` | `google-beta` | Custom domain(s) for the backend (one per `custom_domains` entry) |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `backend_id` | `string` | (required) | Backend ID (= Firebase Console title). Project-unique. `^[a-z][a-z0-9-]{2,30}[a-z0-9]$` |
| `location` | `string` | (required) | Backend location |
| `app_id` | `string` | (required) | Firebase Web App ID to link this backend to (passed from `web-app` / external pin via the root module) |
| `service_account` | `string` | (required) | Compute SA email (already resolved by the root module — empty-string auto-create logic lives in the root, not here) |
| `serving_locality` | `string` | `"GLOBAL_ACCESS"` | `GLOBAL_ACCESS` / `REGION_LOCKED` |
| `custom_domains` | `list(string)` | `[]` | Custom domains to register. Empty → none created. DNS registration is expected on a separate layer. |

## Outputs

| Name | Description |
|------|-------------|
| `name` | App Hosting backend resource name |
| `uri` | Backend URI |
| `custom_domains` | Map keyed by domain; each holds `custom_domain_status` (cert/host/ownership state + nested `required_dns_updates`) for the external DNS layer |

## Related APIs

- `firebaseapphosting.googleapis.com`
- `run.googleapis.com`
- `cloudbuild.googleapis.com`
- `artifactregistry.googleapis.com`

## Invocation condition

Called when `var.app_hosting != null`.

## Out of scope

- Source repository integration (set via Console)
- App Hosting rollout policy
- Build configuration (`apphosting.yaml`)
- DNS record registration for custom domains (only the domain is registered here; `custom_domain_status` — with nested `required_dns_updates` — is emitted for the external DNS layer)

<details><summary>Ja</summary>

- ソースリポジトリ連携 (Console 側で設定)
- App Hosting rollout policy
- ビルド設定 (`apphosting.yaml`)
- カスタムドメインの DNS レコード登録 (ここではドメイン登録のみ。`custom_domain_status` (nested に `required_dns_updates` を含む) を別 DNS レイヤ用に出力)

</details>
