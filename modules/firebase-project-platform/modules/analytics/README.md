# modules/analytics

Placeholder submodule for enabling the Google Analytics for Firebase API.

<details><summary>Ja</summary>

Google Analytics for Firebase API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. An attach point that only enables the relevant API.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |

## Outputs

None.

## Related APIs

- `analyticsadmin.googleapis.com` (auto-enabled by the root module)
- `firebase.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.analytics != null`.

## Out of scope

- Linking a GA4 property (via Console / Analytics Admin API)
- Event / Conversion configuration
- BigQuery export configuration

Manage these via separate tooling.

<details><summary>Ja</summary>

- GA4 property との link 作成 (Console / Analytics Admin API で実施)
- Event / Conversion 設定
- BigQuery export 設定

これらは別途運用ツールで管理する。

</details>
