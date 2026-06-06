# modules/firebase

Submodule that **Firebase-enables** a GCP Project.

<details><summary>Ja</summary>

GCP Project を **Firebase 化** する submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_firebase_project.this` | `google-beta` | Enables the GCP Project as a Firebase Project |

<details><summary>Ja</summary>

GCP Project を Firebase Project として有効化する。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |

## Outputs

| Name | Description |
|------|-------------|
| `project_id` | Firebase project ID |
| `display_name` | Firebase project display name |

## Related APIs

- `firebase.googleapis.com` (auto-enabled by the root module)

## Invocation condition

Called when `var.firebase != null` (default `true`). Setting it to `null` skips Firebase-enablement; while other Firebase-family submodules (`auth`, `firestore`, `hosting`, etc.) will skip the `module.firebase` dependency, resources that genuinely require a Firebase Project will still fail. **In practice, leave it as `true`.**

<details><summary>Ja</summary>

`var.firebase != null` (デフォルト `true`) の場合に呼び出される。これを `null` にすると Firebase 化されず、他の Firebase 系 submodule (`auth`, `firestore`, `hosting` 等) も依存解決のために `module.firebase` を待たないだけで、本来 Firebase 化前提のリソース作成はエラーになりうる。**通常は `true` のままにする**。

</details>
