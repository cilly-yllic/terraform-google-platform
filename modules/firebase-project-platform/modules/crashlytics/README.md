# modules/crashlytics

Placeholder submodule for enabling the Firebase Crashlytics API.

<details><summary>Ja</summary>

Firebase Crashlytics API 有効化のためのプレースホルダ submodule。

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

- `firebasecrashlytics.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.crashlytics != null`.

## Out of scope

Crashlytics is primarily SDK setup + event reporting; there are essentially no server-side settings to manage.

<details><summary>Ja</summary>

Crashlytics は SDK 側のセットアップとイベント送信が中心で、サーバー側で管理する設定は基本的にない。

</details>
