# modules/hosting

Submodule that creates a Firebase Hosting **site** and links it to an existing Firebase Web App.

The Web App itself is **not** created here — it is created by the `web-app` submodule (one per `apps[]` of `type: "web"`), and its `app_id` is passed in by the root module.

<details><summary>Ja</summary>

Firebase Hosting の **site** を作成し、既存の Firebase Web App に link する submodule。

Web App 自体はこの submodule では作らない。`web-app` submodule (`type: "web"` の `apps[]` ごとに 1 つ) が作成し、その `app_id` をルートモジュールが渡す。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_hosting_site.this` | `google-beta` | Hosting site (linked to the Web App referenced by `app_id`) |
| `google_firebase_hosting_custom_domain.this` | `google-beta` | Custom domain(s) for the site (one per `custom_domains` entry, `wait_dns_verification = false`) |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `site_id` | `string` | (required) | Hosting site ID (= subdomain). Globally unique. |
| `app_id` | `string` | (required) | Firebase Web App ID to link this site to (passed from `web-app` via the root module) |
| `custom_domains` | `list(string)` | `[]` | Custom domains to register. Empty → none created. DNS registration is expected on a separate layer (`wait_dns_verification = false`). |

## Outputs

| Name | Description |
|------|-------------|
| `site_id` | Site ID actually used |
| `app_id` | Linked Firebase Web App ID (used for App Hosting wiring) |
| `default_url` | Hosting site default URL |
| `custom_domains` | Map keyed by domain; each holds `required_dns_updates` for the external DNS layer |

## Related APIs

- `firebasehosting.googleapis.com`

## Invocation condition

Called when `var.hosting != null`.

## Out of scope

- Hosting deploy (`firebase deploy --only hosting`)
- rewrites / redirects / headers
- DNS record registration for custom domains (the resource only registers the domain and emits `required_dns_updates`; the actual DNS records are applied on a separate layer)
- GitHub Integration

These are managed via Firebase CLI or other operational tooling.

<details><summary>Ja</summary>

- Hosting deploy (`firebase deploy --only hosting`)
- rewrites / redirects / headers
- カスタムドメインの DNS レコード登録 (このリソースはドメイン登録と `required_dns_updates` 出力のみ。実際の DNS レコードは別レイヤで設定する)
- GitHub Integration

これらは Firebase CLI または別途運用ツールで管理する。

</details>
