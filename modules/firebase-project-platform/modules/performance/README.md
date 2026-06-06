# modules/performance

Placeholder submodule for enabling the Firebase Performance Monitoring API.

<details><summary>Ja</summary>

Firebase Performance Monitoring API 有効化のためのプレースホルダ submodule。

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

- `firebaseperformance.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.performance != null`.

## Out of scope

Custom traces / instrumentation are set up via the SDK.

<details><summary>Ja</summary>

カスタムトレース / 計測設定は SDK 側で行う。

</details>
