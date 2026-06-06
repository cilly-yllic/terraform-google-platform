# Variables reference

Complete reference for each feature variable's nested structure and defaults. For the raw type definitions, see [`variables.tf`](../variables.tf).

<details><summary>Ja</summary>

各機能変数のネスト構造とデフォルト値の完全リファレンス。型定義そのものは [`variables.tf`](../variables.tf) を参照。

</details>

---

## Three-pattern values

Every feature variable accepts one of:

| Value | Behavior |
|-------|----------|
| `null` (= omitted) | **Disabled.** No resources / APIs / IAM are created. |
| `true` | Enabled with default settings. |
| `{ ... }` (object) | Enabled with custom values; unspecified fields use defaults. |

Only the `firebase` variable defaults to `true` (always Firebase-enable). Everything else defaults to `null`.

<details><summary>Ja</summary>

すべての機能変数は次の 3 パターンを受け付ける:

- `null` (= 省略) → 無効。関連リソース / API / IAM は一切作成しない
- `true` → デフォルト設定で有効化
- `{ ... }` (object) → 指定した項目をカスタム値で有効化、未指定項目はデフォルト値

`firebase` 変数のみデフォルト値が `true` (= 常に Firebase 化される)。それ以外はすべて `null` がデフォルト。

</details>

---

## Project settings

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `project_id` | `string` | (required) | GCP / Firebase project ID. Validated against `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`. |
| `region` | `string` | `"asia-northeast1"` | Default location for each feature. Validated against `^[a-z]+-[a-z]+[0-9]+$`. |
| `billing_account` | `string` | `""` | Billing account ID (`XXXXXX-XXXXXX-XXXXXX`). Empty string skips billing association. |

<details><summary>Ja</summary>

- `project_id` (string, required): GCP / Firebase project ID。`^[a-z][a-z0-9-]{4,28}[a-z0-9]$` のバリデーションあり
- `region` (string, default `"asia-northeast1"`): 各機能のデフォルト location。`^[a-z]+-[a-z]+[0-9]+$` のバリデーションあり
- `billing_account` (string, default `""`): Billing account ID (`XXXXXX-XXXXXX-XXXXXX`)。空文字なら billing 関連付けを行わない

</details>

---

## Firebase core

### `firebase`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| (root) | `null / true` | `true` | Firebase-enable the Project. Recommended to leave on. |

<details><summary>Ja</summary>

Firebase Project 化。常に有効推奨。

</details>

### `authentication`

Identity Platform configuration.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `blocking_functions.before_create` | `string` | `""` | Cloud Function URI for the `beforeCreate` Identity Platform trigger |
| `blocking_functions.before_sign_in` | `string` | `""` | Cloud Function URI for the `beforeSignIn` Identity Platform trigger |

Providing just `{}` (= equivalent to defaults) is enough to create the Identity Platform config.

<details><summary>Ja</summary>

Identity Platform 設定。

- `blocking_functions.before_create` (string, default `""`): Cloud Function URI (Identity Platform `beforeCreate` トリガー)
- `blocking_functions.before_sign_in` (string, default `""`): Cloud Function URI (Identity Platform `beforeSignIn` トリガー)

`{}` のみ指定 (=デフォルト相当) で Identity Platform config が作成される。

</details>

### `firestore`

The default database is **always created** with a **deny-all** initial ruleset (production rules are expected to be deployed via Firebase CLI).

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `location` | `string` | `var.region` | Default DB location |
| `type` | `string` | `"FIRESTORE_NATIVE"` | `FIRESTORE_NATIVE` / `DATASTORE_MODE` |
| `delete_protection_state` | `string` | `"DELETE_PROTECTION_DISABLED"` | `DELETE_PROTECTION_DISABLED` / `DELETE_PROTECTION_ENABLED` |
| `point_in_time_recovery` | `bool` | `false` | PITR |
| `databases` | `list(object)` | `[]` | Additional databases |
| `databases[].database_id` | `string` | (required) | database ID |
| `databases[].location` | `string` | Same as default DB | location |
| `databases[].type` | `string` | `"FIRESTORE_NATIVE"` | type |
| `databases[].delete_protection_state` | `string` | `"DELETE_PROTECTION_DISABLED"` | |
| `databases[].point_in_time_recovery` | `bool` | `false` | |

<details><summary>Ja</summary>

デフォルト database は **常に作成** され、初期 ruleset として **deny-all** が書き込まれる (本番ルールは Firebase CLI で更新する前提)。

</details>

### `rtdb`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `location` | `string` | `var.region` | RTDB instance location |
| `type` | `string` | `"DEFAULT_DATABASE"` | `DEFAULT_DATABASE` / `USER_DATABASE` |

The instance ID is fixed at `{project_id}-default-rtdb`.

<details><summary>Ja</summary>

instance ID は `{project_id}-default-rtdb` 固定。

</details>

### `storage`

The default bucket (`{project_id}.firebasestorage.app`) is **always created** with a **deny-all** initial ruleset.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `buckets` | `list(object)` | `[]` | Additional buckets |
| `buckets[].name` | `string` | (required) | bucket name (prefixed with `{project_id}-` by default) |
| `buckets[].raw_name` | `bool` | `false` | `true` skips the prefix and uses `name` verbatim |
| `buckets[].location` | `string` | `var.region` | bucket location |
| `buckets[].storage_class` | `string` | `"REGIONAL"` | storage class |
| `buckets[].iams` | `list(object)` | `[]` | IAM bindings (`role`, `members`) |
| `firestore_backup` | `object \| null` | `null` | Firestore backup bucket config |
| `firestore_backup.bucket_name` | `string` | `"firestore-backups"` | suffix (expanded to `{project_id}-<suffix>`) |
| `firestore_backup.export_platform` | `string` | `"cloud_functions"` | `cloud_functions` / `cloud_run`. Selects which SA receives Firestore-export IAM. |
| `firestore_backup.soft_delete_policy.retention_duration_seconds` | `number` | `0` | Soft-delete retention seconds (0 disables) |

<details><summary>Ja</summary>

デフォルト bucket (`{project_id}.firebasestorage.app`) は **常に作成** され、初期 ruleset として **deny-all** が書き込まれる。

</details>

### `hosting`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `site_id` | `string` | `var.project_id` | Hosting site ID. Empty falls back to project_id. |

Creates both a Web App and a Hosting site.

<details><summary>Ja</summary>

Web App と Hosting site の両方を作成する。

</details>

### `app_hosting`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `location` | `string` | `var.region` | backend location |
| `app_id` | `string` | (required, usually the `app_id` from `hosting`) | Firebase Web App ID |
| `service_account` | `string` | (auto-created) | Compute SA email. Empty creates `firebase-app-hosting-compute` and grants `roles/firebaseapphosting.computeRunner`. |
| `serving_locality` | `string` | `"GLOBAL_ACCESS"` | `GLOBAL_ACCESS` / `REGION_LOCKED` |

Backend ID is fixed at `{project_id}-app-hosting`.

<details><summary>Ja</summary>

backend ID は `{project_id}-app-hosting` 固定。

</details>

### `data_connect`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `location` | `string` | `var.region` | Data Connect service location |
| `service_id` | `string` | `"{project_id}-dataconnect"` | service ID |
| `cloud_sql` | `object \| null` | `null` | Cloud SQL instance config (null skips Cloud SQL) |
| `cloud_sql.instance_id` | `string` | `"{project_id}-fdc"` | instance name |
| `cloud_sql.database` | `string` | `project_id` | database name |
| `cloud_sql.tier` | `string` | `"db-f1-micro"` | machine tier |
| `cloud_sql.database_version` | `string` | `"POSTGRES_15"` | PostgreSQL version |
| `cloud_sql.deletion_protection` | `bool` | `false` | Destroy protection |

---

## Firebase extensions

All accept only `null / true` (API-only placeholders).

| Name | API enabled |
|------|-------------|
| `fcm` | `fcm.googleapis.com` |
| `remote_config` | `firebaseremoteconfig.googleapis.com` |
| `app_check` | `firebaseappcheck.googleapis.com` |
| `crashlytics` | `firebasecrashlytics.googleapis.com` |
| `performance` | `firebaseperformance.googleapis.com` |
| `analytics` | `analyticsadmin.googleapis.com`, `firebase.googleapis.com` |
| `extensions` | `firebaseextensions.googleapis.com` |

<details><summary>Ja</summary>

すべて API 有効化のみ (`null / true` のみ受け付ける placeholder)。

</details>

---

## GCP services

### `secret_manager`, `pubsub`, `cloud_run`, `cloud_functions`

Accept `null / true` only — API-enable triggers. Secrets / topics / functions themselves are not created here.

Setting `cloud_run` / `cloud_functions` to `true` also makes them participate in IAM auto-derivation (the CI SA gets `roles/run.admin`, etc.).

<details><summary>Ja</summary>

`null / true` のみ受け付ける API 有効化トリガー。secret / topic / function 自体は本モジュールでは作成せず、別途管理する。

`cloud_run` / `cloud_functions` は `true` にすると IAM auto-determine 対象になる (CI SA に `roles/run.admin` 等が自動付与)。

</details>

### `cloud_tasks`, `cloud_scheduler`, `eventarc`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `location` | `string` | `var.region` | location |

---

## API management

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `additional_apis` | `list(string)` | `[]` | Extra APIs to enable beyond auto-derivation. Each entry must end with `.googleapis.com`. |

---

## IAM

### `users`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `email` | `string` | (required) | user email |
| `role` | `string` | `"viewer"` | One of `viewer` / `editor` / `owner` |
| `deploy` | `bool` | `false` | `true` additionally grants `roles/cloudfunctions.admin` + `roles/artifactregistry.reader` |

### `ci_service_account`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `account_id` | `string` | `"ci-deploy"` | SA ID |
| `display_name` | `string` | `"CI/CD Deployment"` | display name |
| `additional_roles` | `list(string)` | `[]` | Roles to grant in addition to the auto-derived set |

The roles set is auto-derived from feature flags. See [service-accounts.md](./service-accounts.md).

<details><summary>Ja</summary>

roles は機能 on/off から自動決定される。詳細は [service-accounts.md](./service-accounts.md)。

</details>

### `service_accounts`

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `account_id` | `string` | (required) | SA ID |
| `display_name` | `string` | Same as `account_id` | display name |
| `type` | `string` | (required) | Currently only `"deploy"` |
| `roles` | `list(string)` | `[]` | Additional explicit roles |
| `args` | `object` | `{}` | Feature flags for `type = "deploy"` (see below) |

`args` fields for `type = "deploy"`:

| Field | Auto-granted roles |
|-------|-------------------|
| `hosting` | `roles/firebasehosting.admin` |
| `functions` | `roles/cloudfunctions.admin`, `roles/iam.serviceAccountUser`, `roles/artifactregistry.admin` |
| `firestore` | `roles/datastore.indexAdmin`, `roles/firebaserules.admin` |
| `storage` | `roles/firebasestorage.viewer`, `roles/storage.objectAdmin`, `roles/storage.admin` |
| `scheduler` | `roles/cloudscheduler.admin` |
| `tasks` | `roles/cloudtasks.queueAdmin` |
| `blocking` | `roles/firebaseauth.admin` |

All SAs get `roles/runtimeconfig.admin` in common.

<details><summary>Ja</summary>

全 SA に共通で `roles/runtimeconfig.admin` が付与される。

</details>
