# modules/hosting

Submodule that creates a Firebase Hosting **Web App + Hosting site**.

<details><summary>Ja</summary>

Firebase Hosting の **Web App + Hosting site** を作成する submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_web_app.this` | `google-beta` | Firebase Web App (uses `site_id` as the display name) |
| `google_firebase_hosting_site.this` | `google-beta` | Hosting site (linked to the Web App) |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `site_id` | `string` | `var.project` (empty falls back to project ID) | Hosting site ID |

## Outputs

| Name | Description |
|------|-------------|
| `site_id` | Site ID actually used |
| `app_id` | Firebase Web App ID (used for App Hosting wiring) |
| `default_url` | Hosting site default URL |

## Related APIs

- `firebasehosting.googleapis.com`

## Invocation condition

Called when `var.hosting != null`.

## Out of scope

- Hosting deploy (`firebase deploy --only hosting`)
- rewrites / redirects / headers
- Custom domains
- GitHub Integration

These are managed via Firebase CLI or other operational tooling.

<details><summary>Ja</summary>

- Hosting deploy (`firebase deploy --only hosting`)
- rewrites / redirects / headers
- カスタムドメイン
- GitHub Integration

これらは Firebase CLI または別途運用ツールで管理する。

</details>
