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

Called when `var.authentication != null`, `authentication.upgrade_to_identity_platform` is not `false`, and `authentication.blocking_functions.managed_by` is not `"deploy"`.

## Side effects

Identity Platform config is a **singleton per GCP Project** — once created, it cannot be deleted from the Console.

<details><summary>Ja</summary>

Identity Platform config は **GCP Project に 1 つだけ存在する singleton resource**。一度作成すると Console から削除できない点に注意。

</details>

## Blocking functions owned by `firebase deploy`

This module manages the triggers from `blocking_functions` (empty → no triggers, so triggers registered by `firebase deploy` are removed on the next apply). To leave them to `firebase deploy`, set `authentication.blocking_functions.managed_by = "deploy"` in the root module; it then calls [`modules/auth-deploy-managed`](../auth-deploy-managed/README.md) instead.

<details><summary>Ja</summary>

この module は `blocking_functions` で trigger を管理する (空なら trigger 無しにするため、`firebase deploy` が登録した trigger は次の apply で消える)。`firebase deploy` に任せる場合は root module で `authentication.blocking_functions.managed_by = "deploy"` にすると、代わりに [`modules/auth-deploy-managed`](../auth-deploy-managed/README.md) が呼ばれる。

</details>

## Upgrading to Identity Platform

Creating `google_identity_platform_config` calls `initializeAuth`, which **upgrades the project to Identity Platform**. The root module controls this with two flags under `authentication`:

| Situation | Setting |
|-----------|---------|
| Let Terraform upgrade the project (default) | `upgrade_to_identity_platform` omitted / `true` |
| Keep Firebase Authentication without upgrading | `upgrade_to_identity_platform = false` (only the API and IAM are managed; this submodule is not called) |
| Already upgraded from the Console | `import_existing = true` (creating it again would fail because the config already exists) |

`import` blocks are only allowed in the root module, so this module cannot import by itself. The dispatch-firebase-platform Action's root template contains the block below and enables it from `authentication.import_existing`. When you call the module directly, add the same block to your root module (replace `firebase_platform` with your module name). Once the config is in state the import is a no-op, so the flag can stay `true`.

```hcl
import {
  for_each = try(tobool(var.authentication.import_existing), false) ? toset(["existing"]) : toset([])

  # blocking_functions.managed_by = "deploy" のときは
  # module.firebase_platform.module.auth_deploy_managed[0].google_identity_platform_config.this
  to = module.firebase_platform.module.auth[0].google_identity_platform_config.this
  id = "projects/${var.project_id}/config"
}
```

<details><summary>Ja</summary>

`google_identity_platform_config` の作成は `initializeAuth` を呼び、**project を Identity Platform にアップグレードする**。root module の `authentication` 配下の 2 つの flag で制御する。

| 状況 | 設定 |
|------|------|
| Terraform でアップグレードする (既定) | `upgrade_to_identity_platform` 省略 / `true` |
| アップグレードせず Firebase Authentication のまま使う | `upgrade_to_identity_platform = false` (API と IAM のみ管理し、この submodule は呼ばれない) |
| Console で既にアップグレード済み | `import_existing = true` (config が既に存在するため、作成しようとすると失敗する) |

`import` block は root module にしか書けないため、この module 単体では import できない。dispatch-firebase-platform Action の root テンプレートには上の block が入っており、`authentication.import_existing` で有効化される。module を直接呼ぶ場合は同じ block を自分の root module に書く (`firebase_platform` は自分の module 名に置き換える)。state に取り込み済みなら import は no-op なので、flag は `true` のままでよい。

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
