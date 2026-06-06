# modules/app-check

Placeholder submodule for enabling the Firebase App Check API.

<details><summary>Ja</summary>

Firebase App Check API 有効化のためのプレースホルダ submodule。

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

- `firebaseappcheck.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.app_check != null`.

## Out of scope

- App Check provider registration (reCAPTCHA / DeviceCheck / Play Integrity)
- Per-service App Check token enforce settings

Manage these via Console or the App Check Admin SDK.

<details><summary>Ja</summary>

- App Check provider (reCAPTCHA / DeviceCheck / Play Integrity) の登録
- App Check token enforce 設定 (per service)

これらは Console または App Check Admin SDK で管理する。

</details>
