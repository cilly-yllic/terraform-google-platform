# modules/auth

Submodule for Firebase Authentication / Identity Platform configuration.

<details><summary>Ja</summary>

Firebase Authentication / Identity Platform の設定を行う submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_identity_platform_config.this` | `google-beta` | Identity Platform config (with optional blocking functions) |

The `blocking_functions { triggers { ... } }` block is only added if `blocking_functions.before_create` or `before_sign_in` is non-empty.

<details><summary>Ja</summary>

`blocking_functions.before_create` / `before_sign_in` が空文字でない場合のみ、`blocking_functions { triggers { ... } }` ブロックが追加される。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `blocking_functions.before_create` | `string` | `""` | Cloud Function URI for the `beforeCreate` trigger |
| `blocking_functions.before_sign_in` | `string` | `""` | Cloud Function URI for the `beforeSignIn` trigger |

## Outputs

| Name | Description |
|------|-------------|
| `name` | Identity Platform config resource name (`projects/{project}/config`) |

## Related APIs

- `identitytoolkit.googleapis.com`

## Invocation condition

Called when `var.authentication != null`.

## Side effects

Identity Platform config is a **singleton per GCP Project** — once created, it cannot be deleted from the Console.

<details><summary>Ja</summary>

Identity Platform config は **GCP Project に 1 つだけ存在する singleton resource**。一度作成すると Console から削除できない点に注意。

</details>

## Mapping to Firebase Console

- Console: Authentication → Settings → Blocking functions
- Sign-in method settings per provider (Google / Email / etc.) are out of scope for this module (managed via Console or separate Terraform).

<details><summary>Ja</summary>

- Console: Authentication → Settings → Blocking functions
- 各プロバイダ (Google / Email / 等) の sign-in method 設定はこの module の範疇外 (Console または別途 Terraform 管理)

</details>
