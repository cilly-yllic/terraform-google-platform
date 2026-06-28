# modules/auth

Submodule for Firebase Authentication / Identity Platform configuration.

<details><summary>Ja</summary>

Firebase Authentication / Identity Platform の設定を行う submodule。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_identity_platform_config.this` | `google-beta` | Identity Platform config (with optional blocking functions and OAuth authorized domains) |

The `blocking_functions { triggers { ... } }` block is only added if `blocking_functions.before_create` or `before_sign_in` is non-empty.

`authorized_domains` is **authoritative + computed**: when the input list is empty the attribute is left unset (`null`) so the provider keeps the existing Firebase defaults (`localhost`, `<project>.firebaseapp.com`, `<project>.web.app`); when non-empty it fully replaces the list. The merge of defaults / localhost and the aggregation of hosting / app_hosting custom domains is done by the **root module**, not here — this submodule just applies the final list.

<details><summary>Ja</summary>

`blocking_functions.before_create` / `before_sign_in` が空文字でない場合のみ、`blocking_functions { triggers { ... } }` ブロックが追加される。

`authorized_domains` は **authoritative + computed**。入力 list が空のときは attribute を設定せず (`null`)、既存の Firebase デフォルト (`localhost` / `<project>.firebaseapp.com` / `<project>.web.app`) を温存する。非空なら全置換する。デフォルト / localhost のマージや hosting / app_hosting の custom domain 集約は **ルートモジュール側**で行い、この submodule は最終 list を適用するだけ。

</details>

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `blocking_functions.before_create` | `string` | `""` | Cloud Function URI for the `beforeCreate` trigger |
| `blocking_functions.before_sign_in` | `string` | `""` | Cloud Function URI for the `beforeSignIn` trigger |
| `authorized_domains` | `list(string)` | `[]` | Final, fully-resolved OAuth authorized-domain list (the root module merges defaults / localhost and aggregates hosting domains). Empty → the attribute is left unset and the provider keeps the existing (Firebase default) value. Non-empty → the list is applied **authoritatively** (full replace). |

## Outputs

| Name | Description |
|------|-------------|
| `name` | Identity Platform config resource name (`projects/{project}/config`) |
| `authorized_domains` | Effective OAuth authorized domains (provider-computed when not managed) |

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
- Console: Authentication → Settings → Authorized domains (`authorized_domains`)
- Sign-in method settings per provider (Google / Email / etc.) are out of scope for this module (managed via Console or separate Terraform).

<details><summary>Ja</summary>

- Console: Authentication → Settings → Blocking functions
- Console: Authentication → Settings → Authorized domains (`authorized_domains`)
- 各プロバイダ (Google / Email / 等) の sign-in method 設定はこの module の範疇外 (Console または別途 Terraform 管理)

</details>
