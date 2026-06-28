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
| `app_hosting` | `roles/firebaseapphosting.admin`, `roles/iam.serviceAccountUser`, `roles/iam.serviceAccountCreator`, `roles/resourcemanager.projectIamAdmin` (the last is Owner-class; see [app-hosting.md](./app-hosting.md)) |
| `cloud_functions` | `roles/cloudfunctions.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.admin` |
| `firestore` | `roles/datastore.indexAdmin`, `roles/firebaserules.admin` |
| `data_connect` | `roles/firebasedataconnect.admin`, `roles/cloudsql.admin` |
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
- `ci_service_account_wif_members` — WIF principalSet members bound to the CI SA (`[]` if `wif` is omitted)

### Workload Identity Federation (optional)

外部 CI (GitHub Actions / Terraform Cloud / GitLab CI 等) から CI SA を **OIDC + WIF** で impersonate したい場合に使う。`wif` を省略すれば binding は作られず、従来通り SA key 等の運用に委ねる。

```hcl
ci_service_account = {
  account_id = "ci-deploy"
  wif = {
    # project-bootstrap が用意した WIF Pool を指す。
    # 形式: projects/{bootstrap_project_number}/locations/global/workloadIdentityPools/{pool_id}
    pool_resource_name = "projects/123456789/locations/global/workloadIdentityPools/terraform-cloud"

    # provider-agnostic な (attribute, value) ペアの list。
    # attribute 名は WIF Provider の attribute mapping で公開している
    # `attribute.{name}` の `{name}` 部分。
    principals = [
      { attribute = "repository",          value = "myorg/myrepo" },          # GitHub Actions
      { attribute = "terraform_workspace", value = "graphql-svc-prd-001" },   # Terraform Cloud
      { attribute = "project_path",        value = "mygroup/myproject" },     # GitLab CI
    ]
  }
}
```

`settings.yml` 経由で書く場合は `${BOOTSTRAP_PROJECT_NUMBER}` placeholder を使って bootstrap project number を yml に literal で書かずに orchestrator Secret から注入できる:

```yaml
firebase_platform:
  ci_service_account:
    account_id: ci-deploy
    wif:
      pool_resource_name: "projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/terraform-cloud"
      principals:
        - { attribute: repository,          value: "myorg/${service}" }
        - { attribute: terraform_workspace, value: "${service}-${env}" }
```

`${BOOTSTRAP_PROJECT_NUMBER}` は dispatch-firebase-platform Action の `bootstrap_project_number` input から展開される (詳細は [action README](../../actions/dispatch-firebase-platform/README.md#settingsyml-placeholder-expansion))。

各 entry は `roles/iam.workloadIdentityUser` を CI SA の `google_service_account_iam_member` として bind する。`member` は

```
principalSet://iam.googleapis.com/{pool_resource_name}/attribute.{attribute}/{value}
```

の形になる。同じ `(attribute, value)` を複数回指定しても 1 binding に dedup される。

#### Provider 別 attribute 名 (主要)

| Provider | attribute | 例 |
|---|---|---|
| GitHub Actions (`google-github-actions/auth@v2`) | `repository` | `myorg/myrepo` |
| Terraform Cloud / HCP Terraform | `terraform_workspace` | `svc-prd-001` |
| GitLab CI | `project_path` | `mygroup/myproject` |
| Bitbucket Pipelines | `workspace` | `myworkspace` |

Pool / Provider の attribute mapping 設計は `docs/project-bootstrap/design/wif-attribute-mapping.md` 参照。新規 attribute を使う場合は Provider 側の attribute mapping にも追加が必要。

#### WIF を使わない場合

`wif = null` (= 省略) で binding は作らない。SA key 発行や別経路の impersonation を運用する想定。

<details><summary>Ja</summary>

- `wif` を指定するだけで CI SA に対する `roles/iam.workloadIdentityUser` binding が作られる
- `attribute` / `value` の汎用ペアなので、GitHub / TFC / GitLab / 他 OIDC を schema 変更なしでカバー可能
- 既存の WIF Pool / Provider は project-bootstrap 側で作られている前提 (本モジュールでは新規作成しない)
- 省略すれば binding は作られないので、従来運用 (key) との互換あり

</details>

---

## Additional Service Accounts (`service_accounts`)

SAs for purposes other than CI (app runtime, batch jobs, external integrations). `type = "deploy"` enables the `args` sugar roles; any other `type` (e.g. `"reader"`) grants only the explicit `roles` list. An optional `wif` block (same shape as `ci_service_account.wif`) lets external CI impersonate the SA keylessly.

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

### Read-only SA + WIF (例: custom domain DNS reader)

deploy SA は admin 権限を持つため、custom domain の DNS 要件 (`requiredDnsUpdates`) を
**読むだけ**の用途には強すぎる。read-only SA を別に切り、WIF で project repo の
GitHub Actions から keyless impersonate させると最小権限で済む。

```hcl
service_accounts = [
  {
    account_id   = "dns-reader"
    display_name = "Custom Domain DNS Reader"
    type         = "reader" # deploy 以外 → args sugar 無し、roles だけ付与
    roles = [
      "roles/firebasehosting.viewer",    # Hosting site / custom domain 読取
      "roles/firebaseapphosting.viewer", # App Hosting backend / domain 読取
    ]
    wif = {
      # WIF *Pool* のパス (末尾に /providers/... は付けない)。
      pool_resource_name = "projects/123456789/locations/global/workloadIdentityPools/terraform-cloud"
      principals = [
        { attribute = "repository", value = "my-org/my-service" },
      ]
    }
  },
]
```

`wif` の形式・attribute 名は [CI SA の WIF セクション](#workload-identity-federation-optional) と同じ。

### Outputs

- `service_account_emails` — `{ account_id => email }`
- `service_account_roles` — `{ account_id => [roles...] }`
- `service_account_wif_members` — `{ binding_id => member }` (manual SA の WIF binding。`wif` 未設定なら `{}`)

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
