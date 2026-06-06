# modules/pubsub

Placeholder submodule for enabling the Pub/Sub API.

<details><summary>Ja</summary>

Pub/Sub API 有効化のためのプレースホルダ submodule。

</details>

## Resources created

None. Topics / subscriptions are not created by this module.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |

## Outputs

None.

## Related APIs

- `pubsub.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.pubsub != null`.

## Design intent

Pub/Sub is typically combined with Eventarc / Cloud Functions / Cloud Run for service-specific domain logic, so this module limits itself to API enablement.

<details><summary>Ja</summary>

Pub/Sub は Eventarc / Cloud Functions / Cloud Run と組み合わせて service 固有のドメイン用途に使われることが多く、本モジュールでは API 有効化のみに留めている。

</details>
