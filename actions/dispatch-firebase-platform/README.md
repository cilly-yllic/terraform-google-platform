# dispatch-tfc-firebase-platform

A GitHub Action that starts Terraform Cloud Runs for the Firebase Platform.

`settings.yml` を起点に対象 env を選別し、各 env ごとに **`{service}-{env}` workspace upsert → 変数同期 → Run 作成**を順次実行する。env を `settings.yml` から削除した際は同タグ workspace を自動 force-delete し、TFC 上の孤児 workspace を残さない（GCP リソースの destroy は Action A の責務）。

This corresponds to **Action B** (`dispatch-tfc-firebase-platform`). Action A (`dispatch-tfc-project-bootstrap`) lives in [`actions/dispatch-project-bootstrap/`](../dispatch-project-bootstrap/) and handles the project-bootstrap stage.

> **Related docs**: [architecture.md](../../docs/project-bootstrap/architecture.md) / [related-components.md](../../docs/project-bootstrap/related-components.md)

---

## Usage

### 単一 env を指定する場合

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    environment: dev-001
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

### labels で複数 env を順次 dispatch する場合

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    # environment 未指定 → settings.environments 全件が候補
    labels: '["^tier:dev$"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

`environment` と `labels` の **少なくとも一方**は必須。両方未指定の場合は error 終了する。

## Inputs

| Name | Required | Default | Description |
|------|:--------:|---------|-------------|
| `service` | yes | — | Service name |
| `environment` | no | `""` | 対象 env キー。未指定なら `settings.environments` 全件が候補。`labels` と AND 評価される |
| `settings_path` | no | `terraform/settings.yml` | Path to settings.yml |
| `tfc_org` | yes | — | Terraform Cloud organization name |
| `target_workspace` | no | `{service}-{environment}` | 作成する workspace 名パターン (`{service}`, `{environment}` placeholder) |
| `bootstrap_project_id` | no | `infra-bootstrap` | GCP bootstrap project ID (for Workload Identity) |
| `bootstrap_project_number` | yes | — | GCP bootstrap project number (numeric, for WIF path) |
| `workload_identity_pool_id` | no | `terraform-cloud` | Workload Identity Pool ID |
| `workload_identity_provider_id` | no | `terraform-cloud` | Workload Identity Provider ID |
| `tfc_token` | yes | — | Terraform Cloud API token |
| `apply_policy` | no | `env-based` | Run apply policy: `auto` / `manual` / `env-based` |
| `enable_webhook_notification` | no | `false` | Phase 2 webhook notification を設定するか |
| `cloud_run_webhook_url` | no | — | Cloud Run router URL (webhook 有効時必須) |
| `cloud_run_webhook_secret` | no | — | HMAC secret (Cloud Run router と共有、webhook 有効時必須) |
| `module_version` | no | — | Registry module の version 制約 (`1.2.3` や `~> 1.0`)。空なら version 属性を出力せず常に最新を使用 |
| `labels` | no | `""` | JS RegExp パターンの JSON 配列 (`'["^tier:dev$","^region:apne1$"]'`)。各 env の `labels` が全パターンに一致 (AND) しないと対象から外れる |

## Outputs

| Name | Description |
|------|-------------|
| `applied_envs` | JSON 配列。今回 Run を作成した env キー (e.g. `["prd-001","dev-002"]`) |
| `filtered_envs` | JSON 配列。`status: inactive` や labels 不一致で対象から外された env と理由 (`[{env, reason, detail}]`) |
| `failed_envs` | JSON 配列。ループ内で個別失敗した env と error 詳細 (`[{env, error}]`) |
| `destroyed_envs` | JSON 配列。`environments:` `retained_envs:` 両方から消えて TFC workspace を force-delete した env キー。GCP リソースは A が destroy |
| `retained_envs` | JSON 配列。`environments:` から消えたが `retained_envs:` で保護され、workspace を残した env キー |
| `run_ids` | JSON object。env → Run ID のマップ (e.g. `{"prd-001":"run-xyz"}`) |
| `run_urls` | JSON object。env → Run URL のマップ |
| `workspace_ids` | JSON object。env → Workspace ID のマップ |
| `workspace_names` | JSON object。env → Workspace name のマップ |
| `skipped` | `"true"` if no env was dispatched and no workspace was deleted、`"false"` otherwise |
| `skip_reason` | `skipped=true` 時の理由コード: `no_changes` (それ以外は空) |

`failed_envs` が非空のときは `core.setFailed` も呼ばれる（既に成功した env の Run はキャンセルされない）。

---

## Apply policy

`apply_policy` input で Run の auto-apply を制御する。

| Value | Behavior |
|-------|----------|
| `auto` | 全環境で auto-apply |
| `manual` | 全環境で手動承認 |
| `env-based` (default) | env key が `dev` で始まるもの → auto-apply、その他 → 手動承認 |

---

## settings.yml 構造

```yaml
service: my-app

# 削除されても workspace を残したい env のリスト。
# environments: から消えた env が retained_envs にあれば、B は
# workspace を残す（GCP リソースの destroy は A の責務）。
retained_envs:
  - prd-001

environments:
  dev-001:
    # status 省略時は active、labels 省略時は []
    labels:
      - tier:dev
      - region:apne1
    billing_account_id: "BBBB-BBBB-BBBB"
    firebase_platform:
      firebase: true
      firestore:
        location: asia-northeast1
      hosting: true
      storage: true
      authentication: true
  stg-001:
    status: inactive   # 設定は保持しつつ provision は保留
    labels:
      - tier:stg
      - region:apne1
    billing_account_id: "AAAA-AAAA-AAAA"
    firebase_platform:
      firebase: true
  prd-001:
    status: active
    labels:
      - tier:prd
      - region:apne1
    billing_account_id: "AAAA-AAAA-AAAA"
    firebase_platform:
      firebase: true
      firestore: true
      hosting: true
      storage: true
```

各 feature flag は `null` (省略) / `true` / `{ ... }` (custom config) のいずれかを受け取る。設定可能な feature キーの完全リストは `lib/dispatch/index.ts` の `FEATURE_KEYS` / `PASSTHROUGH_KEYS` を参照。完全なサンプルは [`examples/settings.yml`](../../examples/settings.yml)。

| Common field | Type | Default | Purpose |
|------|------|---------|---------|
| `status` | `"active" \| "inactive"` | `"active"` | `inactive` env はゲートで対象外、`filtered_envs` に記録される |
| `labels` | `string[]` | `[]` | Action input `labels` の RegExp と AND 評価される free-form タグ |

---

## Environment gating

各 env を Run 対象に含めるかは以下の 2 段で判定される（Action A と同一ロジック）:

### Gate 1: `status`

`settings.yml` の `environments.<env>.status: inactive` だと**常に**対象外。サービス開発中で設定だけ先に書きたいが、課金される実インフラはまだ立てたくない env で使う。

→ `filtered_envs` に `reason: status_inactive` で記録される。

### Gate 2: `labels` (Action input × env labels, AND match)

Action input `labels` は **JSON 配列の RegExp 文字列**。指定された全パターンが、env の `labels` 配列のいずれかにマッチする必要がある（AND）。input が空ならゲート無効。

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    labels: '["^tier:dev$", "^region:apne1$"]'
    # ...
```

env が `tier:dev` と `region:apne1` の両方にマッチする label を持つときだけ実行。マッチしなければ `filtered_envs` に `reason: labels_mismatch` で記録される。

> **Tips**: パターンは `RegExp.test()` で評価されデフォルトは部分一致。完全一致したい場合は `^...$` で囲む。

---

## ケース挙動表（`environments` ⇄ `retained_envs` ⇄ 既存 workspace）

| `environments` | `retained_envs` | 既存 workspace | 挙動 |
|:---:|:---:|:---:|---|
| ✅ | — | あり/なし | workspace を upsert + Run（ループ内）|
| ❌ | ✅ | あり | **何もしない**（workspace 残す。`retained_envs` 出力に記録）|
| ❌ | ✅ | なし | no-op |
| ❌ | ❌ | あり | **workspace を force-delete**（GCP は A の責務、`destroyed_envs` 出力に記録）|
| ❌ | ❌ | なし | no-op |

リコンシリエーション対象は **`firebase-platform-{service}` タグが付いた workspace のみ**。タグは B が upsert 時に付与するので、他ツールが作った workspace を巻き込むリスクは無い。

---

## Examples

### Phase 1 (orchestrator から呼び出し)

```yaml
jobs:
  firebase-platform:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - id: dispatch
        uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: my-app
          environment: dev-001
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          tfc_token: ${{ secrets.TFC_TOKEN }}
      - run: echo "applied=${{ steps.dispatch.outputs.applied_envs }}"
```

### Phase 2 (Project Repo の workflow から repository_dispatch トリガー)

```yaml
name: Firebase Platform Trigger
on:
  repository_dispatch:
    types: [firebase-platform-trigger]

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: ${{ github.event.client_payload.service }}
          environment: ${{ github.event.client_payload.environment }}
          tfc_org: my-tfc-org
          bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
          apply_policy: env-based
          enable_webhook_notification: "true"
          cloud_run_webhook_url: ${{ secrets.WEBHOOK_URL }}
          cloud_run_webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
```

### labels で dev だけまとめて再 apply

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    labels: '["^tier:dev$"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

→ `dev-001` `dev-002` ... に該当する env の workspace を順次 upsert + Run。

---

## Processing flow

1. `settings.yml` を読み込み、`selectTargetEnvs` で `environment` + `labels` で対象 env を選別
2. 対象 env を**逐次**ループ:
   1. `{service}-{env}` workspace を upsert (存在すれば update、なければ create) + `firebase-platform-{service}` タグを付与
   2. (webhook 有効時) notification config を upsert
   3. `firebase_platform` セクションを HCL 変数にマッピングし、Dynamic Credentials の env vars と共に sync
   4. main.tf / versions.tf を Configuration Version として upload
   5. Run を作成（apply policy を反映）
3. リコンシリエーション:
   1. `firebase-platform-{service}` タグの workspace を一覧
   2. `environments:` にも `retained_envs:` にも無い env の workspace を **force-delete**
4. 集約 outputs を設定。`failed_envs` が非空なら `setFailed`

---

## Notes

- **Full Workspace Management:** B は workspace の変数を完全に管理する。Action が生成しない変数（手動追加や他ツール由来）は **毎回削除される**。手動で必要な変数は `settings.yml` の `firebase_platform` セクションに含めるか、別 workspace を使う。
- **API-driven Workspace:** VCS 連携なしの API-driven workspace を作成・管理する。main.tf / versions.tf は Action 同梱で、dispatch のたびに Configuration Version として upload される。
- **GCP リソースは一切触らない:** B は TFC workspace の lifecycle と中身（variable / Run）のみを管理。GCP project / SA / IAM の destroy は Action A の `for_each` 差分に委譲。これにより A の state を汚染することなく B が workspace を自由に force-delete できる。
- **タグ命名:** リコンシリエーション用タグは `firebase-platform-{service}` 固定。複数 service を同じ TFC org に同居させても互いに巻き込まない。
