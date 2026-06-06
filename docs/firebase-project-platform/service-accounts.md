# Service Accounts

This module manages two kinds of Service Accounts:

| Variable | Use | How roles are decided |
|----------|-----|----------------------|
| `ci_service_account` | A **single shared SA** for CI/CD deploys | **Auto-derived** from feature on/off |
| `service_accounts` | Arbitrary SAs for app runtime / batch / integrations | Specified via per-feature flags in `args` |

The App Hosting compute SA (`firebase-app-hosting-compute`) is created automatically when `app_hosting` is enabled (separate logic).

<details><summary>Ja</summary>

本モジュールが扱う Service Account は次の 2 種類:

- `ci_service_account` — CI/CD で deploy を実行する **共通の 1 SA**。roles は機能 on/off から **自動判定**
- `service_accounts` — アプリ・バッチ・連携用の **任意の SA 群**。`args` で機能フラグを指定

App Hosting 用の compute SA (`firebase-app-hosting-compute`) は `app_hosting` 機能が有効な場合に自動作成される (これは別ロジック)。

</details>

---

## CI Service Account (`ci_service_account`)

### Usage

```hcl
# Disabled
ci_service_account = null

# Enabled with defaults
ci_service_account = true

# Custom
ci_service_account = {
  account_id       = "ci-deploy"
  display_name     = "CI/CD Deployment"
  additional_roles = ["roles/viewer"]
}
```

### Auto-granted roles

When `enable_*` is `true` for a given feature, the following are added (deduped via `distinct()`):

| Feature | Roles granted |
|---------|---------------|
| (always) | `roles/runtimeconfig.admin` |
| `hosting` | `roles/firebasehosting.admin` |
| `cloud_functions` | `roles/cloudfunctions.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.admin` |
| `firestore` | `roles/datastore.indexAdmin`, `roles/firebaserules.admin` |
| `storage` | `roles/firebasestorage.viewer`, `roles/storage.objectAdmin`, `roles/storage.admin` |
| `cloud_scheduler` | `roles/cloudscheduler.admin` |
| `cloud_tasks` | `roles/cloudtasks.queueAdmin` |
| `authentication` | `roles/firebaseauth.admin` |
| `secret_manager` | `roles/secretmanager.admin` |
| `cloud_run` | `roles/run.admin` |

`additional_roles` can stack extra roles on top.

<details><summary>Ja</summary>

`enable_*` が `true` の機能に応じて roles が付与される。重複は `distinct()` で排除される。`additional_roles` で上記に積み増しできる。

</details>

### Outputs

- `ci_service_account_email` — the created SA's email
- `ci_service_account_roles` — the actual list of roles granted

---

## Additional Service Accounts (`service_accounts`)

SAs for purposes other than CI (app runtime, batch jobs, external integrations). Currently only `type = "deploy"` is implemented.

### Usage

```hcl
service_accounts = [
  {
    account_id   = "app-runtime"
    display_name = "App Hosting Runtime SA"
    type         = "deploy"
    args = {
      hosting   = false
      functions = false
      firestore = true
      storage   = true
      scheduler = false
      tasks     = false
      blocking  = false
    }
  },
  {
    account_id = "scheduler-bot"
    type       = "deploy"
    args = {
      scheduler = true
      tasks     = true
    }
  },
]
```

### Roles granted from `args`

Each flag set to `true` adds the listed roles (same logic as `ci_service_account`):

| `args` field | Roles granted |
|--------------|---------------|
| `hosting` | `roles/firebasehosting.admin` |
| `functions` | `roles/cloudfunctions.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.admin` |
| `firestore` | `roles/datastore.indexAdmin`, `roles/firebaserules.admin` |
| `storage` | `roles/firebasestorage.viewer`, `roles/storage.objectAdmin`, `roles/storage.admin` |
| `scheduler` | `roles/cloudscheduler.admin` |
| `tasks` | `roles/cloudtasks.queueAdmin` |
| `blocking` | `roles/firebaseauth.admin` |

All `type = "deploy"` SAs get `roles/runtimeconfig.admin` in common.

Additional ad-hoc roles can be appended via `roles = ["roles/..."]`.

<details><summary>Ja</summary>

`true` にしたフラグごとに roles が付与される。`ci_service_account` と同じロジック。すべての `type = "deploy"` SA に共通で `roles/runtimeconfig.admin` が付与される。任意の追加 role が必要な場合は `roles = ["roles/..."]` を併用する。

</details>

### Outputs

- `service_account_emails` — `{ account_id => email }`
- `service_account_roles` — `{ account_id => [roles...] }`

---

## App Hosting compute SA

When `app_hosting` is enabled and `app_hosting.service_account` is empty (= auto-create), the following SA is created automatically:

- account_id: `firebase-app-hosting-compute`
- granted role: `roles/firebaseapphosting.computeRunner`

To reuse an existing SA, set `app_hosting.service_account = "<email>"` (no SA creation or role grant in that case).

<details><summary>Ja</summary>

`app_hosting` 機能を有効化し、`app_hosting.service_account` を空文字 (= 自動作成) にした場合、`firebase-app-hosting-compute` SA が自動的に作られ、`roles/firebaseapphosting.computeRunner` が付与される。既存の SA を使いたい場合は `app_hosting.service_account = "<email>"` を指定する。

</details>

---

## Best practices

- Keep CI to a single SA (`ci_service_account`).
- Use `service_accounts` for app-runtime SAs — **don't reuse the CI SA** (separation of concerns + cleaner audit logs).
- Set only the minimum necessary flags to `true` in `service_accounts[*].args`.
- If operating Identity Platform blocking functions, allocate an SA with `args.blocking = true` (needs `roles/firebaseauth.admin`).

<details><summary>Ja</summary>

- CI 用の SA は基本 1 個 (`ci_service_account`) に集約する
- アプリランタイム用は **CI SA を流用せず**、`service_accounts` で別 SA を用意する (権限分離 / 監査ログ追跡)
- `service_accounts[*].args` で必要最小限のフラグのみ `true` にする
- Identity Platform の blocking functions を運用する場合は `args.blocking = true` を付ける SA を用意する (`roles/firebaseauth.admin` が必要)

</details>
