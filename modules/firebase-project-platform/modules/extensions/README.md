# modules/extensions

Placeholder submodule for enabling the Firebase Extensions API.

<details><summary>Ja</summary>

Firebase Extensions API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. An attach point that only enables the relevant API.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |

## Outputs

| Name | Description |
|------|-------------|
| `enabled` | Always `true` (constant marker that the feature is enabled) |

## Related APIs

- `firebaseextensions.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.extensions != null`.

## Out of scope

Installing / configuring individual Extensions (`firebase ext:install ...`) is done via the Firebase CLI.

<details><summary>Ja</summary>

各 Extension の install / config (`firebase ext:install ...`) は Firebase CLI で実施する。

</details>
