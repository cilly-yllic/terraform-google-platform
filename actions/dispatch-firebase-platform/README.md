# dispatch-tfc-firebase-platform

A GitHub Action that starts Terraform Cloud Runs for the Firebase Platform.

`settings.yml` を起点に対象 env を選別し、各 env ごとに **`{service}-{env}` workspace upsert → 変数同期 → Run 作成**を順次実行する。env を `settings.yml` から削除した際は同タグ workspace を自動 force-delete し、TFC 上の孤児 workspace を残さない（GCP リソースの destroy は Action A の責務）。

This corresponds to **Action B** (`dispatch-tfc-firebase-platform`). Action A (`dispatch-tfc-project-bootstrap`) lives in [`actions/dispatch-project-bootstrap/`](../dispatch-project-bootstrap/) and handles the project-bootstrap stage.

> **Related docs**: [architecture.md](../../docs/project-bootstrap/architecture.md) / [related-components.md](../../docs/project-bootstrap/related-components.md)

---

## Usage

### env キーを直接指定する場合

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    environments: '["dev-001"]'             # 単一でも JSON 配列で指定
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

複数 env も同じ shape で:

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    environments: '["dev-001","dev-002"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

### labels で複数 env を選別する場合

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    # environments 未指定 → settings.environments 全件が候補
    labels: '["^tier:dev$"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: "123456789012"
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

`environments` (1 件以上) と `labels` (1 件以上) の **少なくとも一方**は必須。両方未指定/空配列の場合は error 終了する。

`environments` で指定したキーが `settings.environments` に存在しない場合は available 一覧と共に error 終了する（drift やタイポを即検出）。

## Inputs

| Name | Required | Default | Description |
|------|:--------:|---------|-------------|
| `service` | yes | — | Service name |
| `environments` | no | `""` | 対象 env キーの JSON 配列文字列 (`'["dev-001","dev-002"]'`)。各キーは `settings.environments` に存在する必要あり (なければ error)。空 / 未指定なら `settings.environments` 全件が候補。`labels` と AND 評価される |
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
| `module_version` | no | — | Registry module の version 制約 (`0.0.0-rc16` や `~> 1.0`)。空なら Action が Terraform Registry を query して **最新版 (pre-release 含む) を auto-resolve** し main.tf に書き込む。Terraform は version 制約なしだと pre-release を選択しない仕様なので、`0.0.0-rcN` しか publish されていない間は空でも壊れない fallback として動く |
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

## Apply 結果通知 (`firebase_platform.notifications`)

apply の結果（success / error / needs_attention）を **TFC notification** 経由で webhook (Slack 等) に通知する。Action B は run を投げたら終わり（poll しない）なので、結果通知は run の終端状態を知っている **TFC が送る**。Action は各 env workspace に notification config を upsert/削除（reconcile）するだけ。

```yaml
firebase_platform:
  notifications:
    # Slack: URL host から自動判定 (destination-type=slack, HMAC 不要、TFC が Slack 整形)
    - url: https://hooks.slack.com/services/T.../B.../xxxx
    # generic webhook (任意の URL)。署名したい場合のみ hmac_secret を付ける
    - url: https://example.com/tfc-hook
      type: generic            # 省略時は host 自動判定 (hooks.slack.com → slack, それ以外 generic)
      triggers:                # 省略時 [run:completed, run:errored, run:needs_attention]
        - run:errored
      hmac_secret: "..."       # generic のみ (X-TFE-Notification-Signature 署名用)
```

| Field | Type | Default | 説明 |
|-------|------|---------|------|
| `url` | `string` | (必須) | 通知先 URL。**空・未設定の entry は skip**（エラーにしない）。Slack URL は機密なのでログは mask される |
| `type` | `slack \| generic \| microsoft-teams` | host 自動判定 | `hooks.slack.com` を含めば `slack`、それ以外 `generic` |
| `triggers` | `string[]` | `[run:completed, run:errored, run:needs_attention]` | TFC notification trigger |
| `hmac_secret` | `string` | (なし) | `generic` のみ。署名 secret |

- **未設定なら no-op**。`notifications` 自体や個々の `url` が無くても **エラーにならない**（オプション機能）。
- 各 entry は `firebase-platform-notify-{index}` という名前の config になる。Phase 2 連鎖用の `firebase-platform-webhook` (generic + HMAC) とは**別名で共存**。
- `notifications` から消した entry は次回 Action B 実行で対応する config を**削除**（reconcile）。
- URL は per-env。全 env 共通にするなら settings.yml の anchor (`&base`) に書く。
- ⚠️ Slack Incoming Webhook URL は実質機密値（その channel に投稿可能）。settings.yml は git に乗るので **private repo 前提**。漏れたら Slack 側で revoke/再発行する。

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
          environments: '["dev-001"]'
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          tfc_token: ${{ secrets.TFC_TOKEN }}
      - run: echo "applied=${{ steps.dispatch.outputs.applied_envs }}"
```

### Phase 2 (Project Repo の workflow から repository_dispatch トリガー)

Cloud Run Router の `client_payload.environments` は **compact JSON 配列文字列** (`["dev-001","dev-002"]`) なので、`toJSON()` を被せず **直接参照で** `environments` input に渡す（matrix なしの 1 invocation で複数 env を処理できる）。

> `toJSON(github.event.client_payload.environments)` は不可。Router が既に文字列化済みのため二重エンコードになり parse に失敗する。詳細は cloud-run-router README "Dispatch payload shape"。

```yaml
name: Firebase Platform Trigger
on:
  repository_dispatch:
    types: [firebase_platform_requested]

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: ${{ github.event.client_payload.service }}
          environments: ${{ github.event.client_payload.environments }}
          tfc_org: my-tfc-org
          # project number は非機密なので Secret ではなく Variable で渡す運用
          bootstrap_project_number: ${{ vars.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
          apply_policy: env-based
```

代わりに B 自身に settings.yml で再解決させたい（drift 許容）場合は labels を中継:

```yaml
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: ${{ github.event.client_payload.service }}
          labels: ${{ github.event.client_payload.labels }}
          tfc_org: my-tfc-org
          bootstrap_project_number: ${{ vars.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

`environments` と `labels` を同時指定した場合: candidates = `environments` で絞り、それを `labels` でさらに AND filter。

### labels で dev だけまとめて再 apply

```yaml
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    labels: '["^tier:dev$"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: ${{ vars.BOOTSTRAP_PROJECT_NUMBER }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

→ `dev-001` `dev-002` ... に該当する env の workspace を順次 upsert + Run。

---

## Processing flow

1. `settings.yml` を読み込み、`selectTargetEnvs` で `environments` (JSON 配列) と `labels` (RegExp 配列) から対象 env を選別
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

---

## settings.yml placeholder expansion

`firebase_platform` 配下の全 string 値を再帰走査して以下の placeholder を展開する。env を跨いで anchor 共有しつつ、env 固有の値や組織共通インフラ識別子だけを分離する用途。

### 命名規約

| 種別 | 規約 | 値の由来 |
|---|---|---|
| YAML-internal placeholder | **lowercase** (例: `${service}` / `${env}`) | service repo の yml SoT (settings.service / 現 env key) |
| External-injected placeholder | **UPPERCASE prefix** (例: `${BOOTSTRAP_PROJECT_NUMBER}`) | orchestrator 側 Secret から Action input 経由で注入 |

利用者が yml を読んだ瞬間に「yml-internal か / 外部注入か」を区別できる。

### サポート placeholder

| Placeholder | 展開される値 | 必須度 |
|---|---|---|
| `${service}` | `settings.service` | 常時利用可 |
| `${env}` | 現 env key (例 `dev-001`) | 常時利用可 |
| `${BOOTSTRAP_PROJECT_NUMBER}` | Action input `bootstrap_project_number` | 参照する場合のみ input 必須 |

### `${BOOTSTRAP_PROJECT_NUMBER}` の使い方

orchestrator workflow から `bootstrap_project_number` input に Secret を渡して、service repo の `settings.yml` ではインフラ識別子を literal で書かずに placeholder を埋め込む。

```yaml
# orchestrator workflow
- uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
  with:
    service: my-app
    environments: '["dev-001"]'
    tfc_org: my-tfc-org
    bootstrap_project_number: ${{ vars.BOOTSTRAP_PROJECT_NUMBER }}
    tfc_token: ${{ secrets.TFC_TOKEN }}
```

```yaml
# service repo settings.yml
service: my-app
environments:
  dev-001:
    firebase_platform:
      ci_service_account:
        account_id: ci-deploy
        wif:
          # ${BOOTSTRAP_PROJECT_NUMBER} は Action 側で展開される
          pool_resource_name: "projects/${BOOTSTRAP_PROJECT_NUMBER}/locations/global/workloadIdentityPools/terraform-cloud"
          principals:
            - { attribute: repository, value: "my-org/${service}" }
            - { attribute: terraform_workspace, value: "${service}-${env}" }
```

### Fail-fast

`settings.yml` で `${BOOTSTRAP_PROJECT_NUMBER}` を **参照しているのに input が空文字 / 未指定** の場合、Action は expand 段階で **fail-fast** で停止する (`projects//locations/...` のような壊れた literal を後続の TFC variable sync に流さない)。逆に **input を指定しても yml で参照していなければ無視** されるので、後方互換は維持される。

### 設計選択ログ (個別 input vs 汎用 map)

- 現状 external 注入が必要な placeholder は `BOOTSTRAP_PROJECT_NUMBER` の 1 件のみ
- `BOOTSTRAP_POOL_ID` (`terraform-cloud`) / `BOOTSTRAP_PROVIDER_ID` (`github-actions`) は project-bootstrap 規約で固定値想定なので、可変化の現実的需要が薄い
- YAGNI 観点で「将来増えるかも」を理由に汎用 map (`external_placeholders: map<string,string>`) にするのは過剰
- **個別 input** の方が schema 明示・型安全・consumer の発見性 (action.yml `inputs` 一覧で見える) で優位
- **refactor トリガー**: external 値が **3 件超** に増える / consumer ごとの任意拡張要件が出る → その時点で `external_placeholders` map に refactor
