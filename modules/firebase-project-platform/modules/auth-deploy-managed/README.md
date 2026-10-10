# modules/auth-deploy-managed

Identity Platform config whose blocking-function triggers are owned by `firebase deploy`. The root module calls this instead of [`modules/auth`](../auth/README.md) when `authentication.blocking_functions.managed_by = "deploy"`.

<details><summary>Ja</summary>

blocking function の trigger を `firebase deploy` に任せる Identity Platform config。root module は `authentication.blocking_functions.managed_by = "deploy"` のとき、[`modules/auth`](../auth/README.md) の代わりにこの module を呼ぶ。

</details>

## Resources created

| Resource | Provider | Role |
|----------|----------|------|
| `google_identity_platform_config.this` | `google-beta` | Identity Platform config with `lifecycle { ignore_changes = [blocking_functions] }` and OAuth authorized domains |

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project` | `string` | (required) | GCP project ID |
| `authorized_domains` | `list(string)` | `[]` | Same as [`modules/auth`](../auth/README.md#inputs): empty → left unset (Firebase defaults kept); non-empty → applied authoritatively |

## Outputs

| Name | Description |
|------|-------------|
| `name` | Identity Platform config resource name (`projects/{project}/config`) |
| `authorized_domains` | Effective OAuth authorized domains |

## Blocking functions: Terraform or `firebase deploy`

Deploying `beforeUserCreated` / `beforeUserSignedIn` with `firebase deploy` registers the triggers in the Identity Platform config. The provider's `blocking_functions` is Optional but **not Computed**, so a config without the block removes those triggers on the next apply. `authentication.blocking_functions.managed_by` in the root module chooses who owns them:

| `managed_by` | Module (config address) | Triggers |
|--------------|-------------------------|----------|
| `terraform` (default) | `module.auth[0]` (`…google_identity_platform_config.this`, unchanged since v1.3.0) | Set from `before_create` / `before_sign_in`. Empty → no triggers (deploy-registered ones are removed) |
| `deploy` | `module.auth_deploy_managed[0]` (`…google_identity_platform_config.this`) | Left to `firebase deploy`. URIs cannot be set |

`ignore_changes` cannot be toggled by a condition, so the two modes are separate modules.

### Switching the mode of an existing config

The config moves to another state address. In the same apply, set `authentication.import_existing = true`:

- The old address is destroyed. The provider cannot delete the config, so this only removes it from state.
- The new address is imported (creating it would fail because the config already exists). The dispatch Action's root template picks the import target from `managed_by`. When calling the module directly, point your `import` block's `to` at the new address.

If you forget `import_existing`, the apply removes the old address from state and then fails to create the new one. The config and its triggers stay on GCP. Re-run with `import_existing = true` to recover.

<details><summary>Ja</summary>

`beforeUserCreated` / `beforeUserSignedIn` を `firebase deploy` すると、Identity Platform config に trigger が登録される。provider の `blocking_functions` は Optional だが **Computed ではない**ため、ブロックを書かない config だと次の apply でその trigger が消える。root module の `authentication.blocking_functions.managed_by` で管理主体を選ぶ。

| `managed_by` | Module (config のアドレス) | Trigger |
|--------------|---------------------------|---------|
| `terraform` (既定) | `module.auth[0]` (`…google_identity_platform_config.this`。v1.3.0 から不変) | `before_create` / `before_sign_in` から設定。空なら trigger 無し (deploy 登録分は消える) |
| `deploy` | `module.auth_deploy_managed[0]` (`…google_identity_platform_config.this`) | `firebase deploy` に任せる。URI は指定不可 |

`ignore_changes` は条件で切り替えられないため、モードごとに module を分けている。

### 既存 config のモードを切り替える

config の state のアドレスが変わる。同じ apply で `authentication.import_existing = true` にする。

- 旧アドレスは destroy されるが、provider は config を削除できないので state から外れるだけ。
- 新アドレスには import する (config が既に存在するため作成は失敗する)。dispatch Action の root テンプレートは `managed_by` に応じて import 先を選ぶ。module を直接呼ぶ場合は `import` block の `to` を新アドレスに向ける。

`import_existing` を忘れると、apply で旧アドレスが state から外れたあと、新アドレスの作成に失敗する。GCP 上の config と trigger は残っているので、`import_existing = true` で再実行すれば復旧できる。

</details>
