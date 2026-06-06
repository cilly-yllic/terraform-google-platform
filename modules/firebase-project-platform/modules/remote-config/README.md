# modules/remote-config

Placeholder submodule for enabling the Firebase Remote Config API.

<details><summary>Ja</summary>

Firebase Remote Config API 有効化のためのプレースホルダ submodule。

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

- `firebaseremoteconfig.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.remote_config != null`.

## Out of scope

Remote Config parameters / conditions / A/B test settings are managed via Console / Firebase CLI / Admin SDK.

<details><summary>Ja</summary>

Remote Config パラメータ / Condition / A/B test 設定はすべて Console / Firebase CLI / Admin SDK で管理する。

</details>
