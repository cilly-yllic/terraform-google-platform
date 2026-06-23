# Variables reference

Complete reference for each feature variable's nested structure and defaults. For the raw type definitions, see [`variables.tf`](../variables.tf).

<details><summary>Ja</summary>

各機能変数のネスト構造とデフォルト値の完全リファレンス。型定義そのものは [`variables.tf`](../variables.tf) を参照。

</details>

---

## settings.yml placeholders (`${service}` / `${env}` / `${BOOTSTRAP_*}`)

dispatch-firebase-platform Action は settings.yml を読んだ後、`firebase_platform` 配下の **全 string 値**を再帰走査して以下の placeholder を展開する:

| placeholder | 展開される値 | 由来 |
|-------------|------------|------|
| `${service}` | settings.yml の top-level `service:` 値 | yml-internal (lowercase = service repo SoT) |
| `${env}` | 現在 dispatch 中の env key (例: `dev-001`) | yml-internal |
| `${BOOTSTRAP_PROJECT_NUMBER}` | Action input `bootstrap_project_number` の値 | external 注入 (UPPERCASE prefix = orchestrator Secret) |

**命名規約**: lowercase = yml 内由来 / UPPERCASE prefix = orchestrator から Action input 経由で注入されるインフラ識別子。yml を読んだ瞬間に「どこから来る値か」が分かるようにしている。

**fail-fast**: `${BOOTSTRAP_PROJECT_NUMBER}` を参照しているのに Action input が空 / 未指定の場合は展開段階で throw (壊れた literal を後段に流さない)。詳細は [action README](../../actions/dispatch-firebase-platform/README.md#settingsyml-placeholder-expansion) を参照。

### よく使う展開箇所

**globally unique 制約があるフィールド** (env / service prefix を入れないと衝突する):

| field | 使い方 |
|-------|--------|
| `hosting[].site_id` | `${service}-${env}-web` (Firebase Hosting site は globally unique) |
| `storage.buckets[].name` | `${service}-${env}-cdn-assets` (GCS bucket は globally unique) |
| `storage.firestore_backup.bucket_name` | `${service}-${env}-firestore-backup` |

`auto_prefix = true` を指定すると、自動で `{project_id}-` が付与される (= 短い base name で衝突しない命名を作る用途)。逆に `${service}` / `${env}` 展開で衝突回避済みの場合は `auto_prefix` 指定不要 (default `false`)。

**project-unique 制約があるフィールド** (区別のため env を入れたい):

| field | 使い方 |
|-------|--------|
| `app_hosting[].backend_id` | `${service}-${env}-api` |
| `firestore[].database_id` | `${env}-analytics` (`"(default)"` は固定文字列なのでそのまま) |
| `data_connect[].service_id` | `main` (固定でも可) |
| `data_connect[].cloud_sql.instance_id` | `${service}-${env}-shared-fdc` |
| `data_connect[].cloud_sql.database` | `${env}-main` |

**cosmetic フィールド** (Firebase Console での見分け用):

| field | 使い方 |
|-------|--------|
| `apps[].display_name` | `"${service} ${env} Main"` (App Store / Play Store とは別、Firebase Console 表示のみ) |

### 主用途

YAML anchor で env を跨いで config を共有しつつ、env 固有の値 (Cloud SQL `instance_id` 等) だけ env-prefix で分離するパターン:

```yaml
service: graphql-svc

_anchors:
  dc_main_cloud_sql: &dc_main_cloud_sql
    instance_id: ${service}-${env}-shared-fdc   # ← Action で展開
    database: main
    tier: db-custom-2-4096

environments:
  dev-001:
    firebase_platform:
      data_connect:
        - service_id: main
          cloud_sql:
            <<: *dc_main_cloud_sql
            tier: db-f1-micro             # dev は小さく override
  prd-001:
    firebase_platform:
      data_connect:
        - service_id: main
          cloud_sql:
            <<: *dc_main_cloud_sql        # 同 anchor を共有
            deletion_protection: true     # prd は protect
```

→ 展開結果:
- dev-001 の `instance_id` = `graphql-svc-dev-001-shared-fdc`
- prd-001 の `instance_id` = `graphql-svc-prd-001-shared-fdc`

### 仕様

- 展開対象は **string 値のみ**。object のキー / number / boolean / null はそのまま
- 未知の placeholder (例: `${unknown}`) はそのまま残る → 後段の HCL render で terraform 用に `$${...}` にエスケープされる (terraform interpolation との混同なし)
- 入力 object は不変 (新オブジェクトを返す)

<details><summary>Ja</summary>

env 跨いで anchor を共有しながら env-specific な値 (instance_id 等) だけ分けたい時に使う placeholder 機構。`${service}` / `${env}` のみサポート、他の `${...}` は terraform 用にスルー & エスケープ。

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

List of Firestore databases (1 project に複数 DB)。各 entry が `google_firestore_database` を作る。`"(default)"` を含めるかは利用者判断 (Firebase SDK の default 動作を期待するなら含める)。

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `database_id` | `string` | (required) | Database ID。`"(default)"` か任意の名前 |
| `location` | `string` | `var.region` | DB location (region / multi-region どちらも可) |
| `type` | `string` | `"FIRESTORE_NATIVE"` | `FIRESTORE_NATIVE` / `DATASTORE_MODE` |
| `delete_protection_state` | `string` | `"DELETE_PROTECTION_DISABLED"` | `DELETE_PROTECTION_DISABLED` / `DELETE_PROTECTION_ENABLED` |
| `point_in_time_recovery` | `bool` | `false` | PITR |

`firestore` が 1 件以上ある場合、project-level の **deny-all** initial ruleset が `cloud.firestore` に自動適用される (本番ルールは Firebase CLI で更新する前提)。

<details><summary>Ja</summary>

複数 Firestore database を 1 project に登録できる array。各 entry は対等で、`(default)` も他の DB と同列に扱われる (auto-create はしない、必要なら明示する)。

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
| `buckets[].name` | `string` | (required) | bucket name (verbatim、globally unique なので呼び出し側で衝突回避を保証) |
| `buckets[].auto_prefix` | `bool` | `false` | `true` で `{project_id}-{name}` に組み立てる |
| `buckets[].location` | `string` | `var.region` | bucket location |
| `buckets[].storage_class` | `string` | `"REGIONAL"` | storage class |
| `buckets[].iams` | `list(object)` | `[]` | IAM bindings (`role`, `members`) |
| `firestore_backup` | `object \| null` | `null` | Firestore backup bucket config |
| `firestore_backup.bucket_name` | `string` | `"firestore-backups"` | bucket 名 (verbatim、`auto_prefix=true` で `{project_id}-` 付与) |
| `firestore_backup.auto_prefix` | `bool` | `false` | `true` で `{project_id}-{bucket_name}` に組み立てる |
| `firestore_backup.export_platform` | `string` | `"cloud_functions"` | `cloud_functions` / `cloud_run`. Selects which SA receives Firestore-export IAM. |
| `firestore_backup.soft_delete_policy.retention_duration_seconds` | `number` | `0` | Soft-delete retention seconds (0 disables) |

<details><summary>Ja</summary>

デフォルト bucket (`{project_id}.firebasestorage.app`) は **常に作成** され、初期 ruleset として **deny-all** が書き込まれる。

</details>

### `apps`

List of Firebase App registrations (Web / iOS / Android を **1 array で discriminated union**)。各 entry は `type` で分岐して対応する Firebase Resource を作る:

| `type` | Firebase Resource | 必須 field | optional field |
|--------|------------------|-----------|---------------|
| `web` | `google_firebase_web_app` | (`name` のみ) | `display_name` |
| `ios` | `google_firebase_apple_app` | `name`, `bundle_id` | `display_name`, `app_store_id`, `team_id` |
| `android` | `google_firebase_android_app` | `name`, `package_name` | `display_name`, `sha1_hashes` (list), `sha256_hashes` (list) |

共通 field:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | `string` | (required) | Internal reference name (type 跨いで unique)。`hosting[].app` / `app_hosting[].app` で参照される key。Rename = destroy-recreate なので immutable 扱い。 |
| `type` | `string` | (required) | `"web"` / `"ios"` / `"android"` |
| `display_name` | `string` | `name` 流用 | Firebase Console 表示名 |

If `apps` is omitted but `hosting` or `app_hosting` is present, a single `{name: "default", type: "web"}` entry is auto-created. `hosting` / `app_hosting` can only reference `type: "web"` entries (Firebase 仕様)。

<details><summary>Ja</summary>

Web / iOS / Android の Firebase App 登録を 1 array で表現する。`type` で discriminate して対応する Firebase Resource (`google_firebase_web_app` / `_apple_app` / `_android_app`) を作る。発行された `app_id` (`1:XXX:web:abc...` 等) は name 経由で `hosting[]` / `app_hosting[]` から参照される (web type のみ link 可)。

`apps` を完全に省略しても、`hosting` / `app_hosting` があれば `default` 名で type=web を 1 件自動作成 + 自動 link される。

</details>

### `hosting`

List of Firebase Hosting sites.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `site_id` | `string` | (required) | Globally unique site ID (URL は `<site_id>.web.app`)。verbatim で扱う。`auto_prefix=true` の時のみ `{project_id}-{site_id}` に組み立てる |
| `auto_prefix` | `bool` | `false` | `true` で `{project_id}-{site_id}` を最終的な site ID として使う (短い base name で衝突回避したい場合用) |
| `app` | `string` | (type=web の app が 1 件のみ時に省略可) | 紐付ける `apps[].name`。**type=web のみ参照可**。複数 / 0 件で省略 / 存在しない名前 / 非 web type を指定 = plan-time error |

<details><summary>Ja</summary>

複数 Hosting site を登録できる list。`app` 省略時、type=web の `apps` が 1 件しかなければ自動 link、複数 / 0 件あるなら plan-time error。

</details>

### `app_hosting`

List of Firebase App Hosting backends.

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `backend_id` | `string` | (required) | Backend ID (project-unique, Firebase Console title)。`[a-z][a-z0-9-]{2,30}[a-z0-9]` |
| `location` | `string` | `var.region` | backend location |
| `app` | `string` | (type=web の app が 1 件のみ時に省略可) | 紐付ける `apps[].name`。**type=web のみ参照可**。`app_id` と排他 |
| `app_id` | `string` | (省略可) | 外部 Web App を pin したい場合のみ指定。`app` と排他 (両方書くと plan-time error) |
| `service_account` | `string` | (auto-created) | Compute SA email。Empty なら project 共有の `firebase-app-hosting-compute` SA を 1 つだけ自動作成して全 backend で共有 |
| `serving_locality` | `string` | `"GLOBAL_ACCESS"` | `GLOBAL_ACCESS` / `REGION_LOCKED` |

<details><summary>Ja</summary>

複数 App Hosting backend を登録できる list。`backend_id` がそのまま Firebase Console のタイトル + terraform 上の backend ID として使われる。

`service_account` を全 backend で省略すれば、project 単位で 1 個の共有 SA (`firebase-app-hosting-compute`) を作って全 backend で使い回す。個別に分けたい場合は entry ごとに指定。

</details>

### `app_hosting_compute_sa_roles`

共有 compute SA (`firebase-app-hosting-compute@<project>`) に**追加で**付与する project-level role の list。`app_hosting` と同階層の top-level key。

| Type | Default | Description |
|------|---------|-------------|
| `list(string)` | `[]` | backend の runtime が他 GCP API を叩く時に必要な role を列挙する。例: Cloud Tasks に enqueue するなら `roles/cloudtasks.enqueuer`。既定の `roles/firebaseapphosting.computeRunner` は自動付与されるので**追加分だけ**を書く。`google_project_iam_member`（non-authoritative）で付与。全 backend に custom `service_account` を指定して共有 SA を作らない構成では no-op。 |

```yaml
firebase_platform:
  app_hosting:
    - backend_id: web-app
      location: asia-northeast1
  app_hosting_compute_sa_roles:
    - roles/cloudtasks.enqueuer
```

詳細・2 段目（invoke 権限）の注意点は [app-hosting.md の Runtime IAM](./app-hosting.md#runtime-iamcompute-sa-に追加権限を付与) を参照。

### `data_connect`

List of Data Connect services (1 project に複数 service)。各 service は GraphQL endpoint を持ち、Cloud SQL Instance + Database を backend にする。

#### Service entry

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `service_id` | `string` | (required) | Data Connect service ID (project-unique) |
| `location` | `string` | `var.region` | Service location |
| `cloud_sql` | `object` | (required) | Cloud SQL backend 設定 (Data Connect は backend 必須) |

#### `cloud_sql` sub-object

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `instance_id` | `string` | (required) | Cloud SQL Instance name。**複数 service が同 instance_id を指せば自動 dedup されて 1 instance に集約** (コスト削減) |
| `database` | `string` | (required) | instance 内の logical database 名。同 instance 内で複数 service が別 database を持てる |
| `tier` | `string` | `"db-f1-micro"` | machine tier (同 instance_id を共有する entries 間で一致必須) |
| `database_version` | `string` | `"POSTGRES_15"` | PostgreSQL version (同様に一致必須) |
| `deletion_protection` | `bool` | `false` | Destroy protection (同様に一致必須) |
| `location` | `string` | `service.location` 流用 | Cloud SQL Instance region (同 instance_id 内で一致必須) |

#### 共有 instance の挙動

複数 service が同じ `instance_id` を指定すると、module 内部で **deduplicate** されて Cloud SQL Instance が 1 つだけ作成される (コスト最適化、月数千円〜の節約)。

一貫性 validation: 同 `instance_id` を持つ entries 間で `tier` / `database_version` / `deletion_protection` / `location` が全て一致する必要あり (不一致は plan-time precondition error)。

<details><summary>Ja</summary>

複数 Data Connect service を 1 project に登録できる array。各 service は Cloud SQL Instance + Database をセットで持つ。

`cloud_sql.instance_id` が同じ entries は自動で **1 つの Cloud SQL Instance に集約**される (Pattern Y、コスト共有モード)。別 `instance_id` を指定すれば独立 instance (Pattern X、性能/region 分離モード)。

Cloud SQL Instance は 1 つの region / tier / database_version しか持てないため、共有モードで properties が食い違うと precondition で plan-time error になる。

</details>

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

### `default_compute_sa_roles`

Compute Engine 既定 SA (`<project-number>-compute@developer`) に**追加で**付与する project-level role の list。`cloud_functions` / `cloud_run` 系の top-level key と同階層。

| Type | Default | Description |
|------|---------|-------------|
| `list(string)` | `[]` | Gen2 Cloud Functions / 既定 Cloud Run の **runtime SA**（専用 SA 未分離の構成ではこの既定 compute SA）が他 GCP API を叩く時に必要な role を列挙。例: function が Secret Manager の値を読むなら `roles/secretmanager.secretAccessor`（既定 SA は `roles/editor` を持つが editor に `secretmanager.versions.access` は含まれない）。既定付与の `run.invoker` / `eventarc.eventReceiver` は自動なので**追加分だけ**書く。`google_project_iam_member`（non-authoritative）で付与。SA email 解決に project number が要るため、本 list が非空なら `cloud_functions` 無効でも `google_project` data を取得する。 |

```yaml
firebase_platform:
  cloud_functions: true
  secret_manager: true
  default_compute_sa_roles:
    - roles/secretmanager.secretAccessor
```

> 注意: 専用 runtime SA を分離していない構成では、この付与は**全 Gen2 functions / 既定 Cloud Run に影響**する。secret 単位に絞るならモジュール外で個別 binding する。App Hosting backend の runtime は別 SA（`firebase-app-hosting-compute`）なので [`app_hosting_compute_sa_roles`](#app_hosting_compute_sa_roles) を使う。

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
| `wif` | `object \| null` | `null` | Optional Workload Identity Federation binding (see below) |

#### `wif` sub-object (optional)

省略すれば WIF binding は作らない (= SA key などで運用)。指定すれば project-bootstrap が用意済みの WIF Pool 上の attribute-based principalSet に対して `roles/iam.workloadIdentityUser` を bind する。

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pool_resource_name` | `string` | (required) | `projects/{bootstrap_pn}/locations/global/workloadIdentityPools/{pool_id}` 形式 |
| `principals` | `list(object)` | (required) | `{attribute, value}` ペアの list (provider-agnostic) |
| `principals[].attribute` | `string` | (required) | WIF Provider の attribute name (例: `repository` / `terraform_workspace` / `project_path`) |
| `principals[].value` | `string` | (required) | attribute の値 (例: `myorg/myrepo` / `svc-prd-001`) |

詳細は [service-accounts.md#workload-identity-federation-optional](./service-accounts.md#workload-identity-federation-optional) 参照。

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
