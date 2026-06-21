# modules/eventarc

Placeholder submodule for enabling the Eventarc API.

<details><summary>Ja</summary>

Eventarc API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. Triggers are not created by this module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `location` | `string` | (required) | Eventarc location |

## Outputs

| Name | Description |
|------|-------------|
| `enabled` | Always `true` (constant marker that Eventarc is enabled) |

## Related APIs

- `eventarc.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.eventarc != null`.

## Design intent

Eventarc triggers are tightly coupled to their targets (Cloud Run / Cloud Functions), so they are expected to be managed alongside the target in a separate Terraform stack.

<details><summary>Ja</summary>

Eventarc trigger は target (Cloud Run / Cloud Function) と密結合するため、target 側の Terraform stack で管理する想定。

</details>
