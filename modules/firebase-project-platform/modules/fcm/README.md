# modules/fcm

Placeholder submodule for enabling the Firebase Cloud Messaging API.

<details><summary>Ja</summary>

Firebase Cloud Messaging API 有効化のためのプレースホルダ submodule。

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

- `fcm.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.fcm != null`.

## Out of scope

- Server-side management of FCM topics / device tokens
- Push notification sending
- Legacy API switching in the Console

Kept as an extension point in case FCM-adjacent resources need to be Terraformed in the future.

<details><summary>Ja</summary>

- FCM Topic / device token のサーバーサイド管理
- Push 通知の送信
- Console での legacy API 切り替え

将来 FCM 周辺リソースを Terraform 化する必要が出た場合の拡張ポイントとして残している。

</details>
