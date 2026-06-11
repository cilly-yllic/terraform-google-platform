# Step 3: GitHub Actions 設定

Project Repository の Workflow で `dispatch-project-bootstrap` (Action A) と `dispatch-firebase-platform` (Action B) を使用する設定を行います。

---

## 前提条件

- [Step 2: TFC セットアップ](./02-tfc-setup.md) が完了済み
- 以下の GitHub Secrets が設定済み:

| Secret | 説明 |
|--------|------|
| `TFC_TOKEN` | Terraform Cloud API Token |
| `WEBHOOK_SECRET` | (Phase 2 のみ) Cloud Run Router と共有する HMAC secret |

> Phase 2 で Cloud Run Router から `repository_dispatch` を発火する場合、Router 側に GitHub App credentials を持たせる構成です。Project Repo 側の workflow には Router 用 secret は不要です。

---

## settings.yml の準備

両 Action が読む共通の `settings.yml` (default: `terraform/settings.yml`) を Project Repository に置きます。

```yaml
service: my-service

# 削除されても Terraform に destroy させたくない env のリスト（任意）。
# environments: から消えても、retained_envs に書かれていれば:
#   - Action A: state からだけ外し、GCP リソースを残す
#   - Action B: workspace を残す（force-delete されない）
retained_envs:
  - prd-001

environments:
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
  dev-001:
    # status / labels は省略可（active / [] が default）
    labels:
      - tier:dev
      - region:apne1
    billing_account_id: "BBBB-BBBB-BBBB"
    firebase_platform:
      firebase: true
      authentication: true
```

完全なサンプル: [`examples/settings.yml`](../../examples/settings.yml)

---

## Action A: dispatch-project-bootstrap

Project Repository の Workflow から Action A を呼び出して GCP Project を作成します。1 サービス = 1 ワークスペース (`project-factory-{service}`) で、`environments` map に複数 env を蓄積して 1 Run で `for_each` 展開します。

### Workflow 例: 単一 env

```yaml
name: Project Bootstrap
on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        type: string
        description: env key (e.g. prd-001)

jobs:
  bootstrap:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
        with:
          service: my-service
          environment: ${{ inputs.environment }}
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          parent_organization_id: "999999999999"
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

### Workflow 例: labels で複数 env を 1 Run にまとめる

```yaml
jobs:
  bootstrap-dev:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
        with:
          service: my-service
          # environment 未指定 → settings.environments 全件が候補
          labels: '["^tier:dev$"]'
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          parent_organization_id: "999999999999"
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

`environment` と `labels` の **少なくとも一方**は必須。両方未指定は error 終了します。

### Outputs を後段で扱う例

```yaml
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
        id: pf
        with: { ... }
      - run: |
          echo "applied=${{ steps.pf.outputs.applied_envs }}"
          echo "destroyed=${{ steps.pf.outputs.destroyed_envs }}"
          echo "filtered=${{ steps.pf.outputs.filtered_envs }}"
      - if: steps.pf.outputs.skipped != 'true'
        run: echo "ran: ${{ steps.pf.outputs.run_url }}"
```

全 Inputs / Outputs: [`actions/dispatch-project-bootstrap/README.md`](../../actions/dispatch-project-bootstrap/README.md)

---

## Action B: dispatch-firebase-platform

Action A が用意したインフラの上に Firebase Platform リソースを構築します。env ごとに `{service}-{env}` workspace を作るので、複数 env を扱う場合は **Action 内で逐次ループ**します。

### Workflow 例: Phase 1 (Polling) / 単一 env

```yaml
name: Firebase Platform
on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        type: string

jobs:
  firebase:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: my-service
          environment: ${{ inputs.environment }}
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

### Workflow 例: Phase 2 (Webhook)

Cloud Run Router からの `client_payload` は **hybrid shape**:

```json
{
  "service": "my-svc",
  "environments": ["dev-001", "dev-002"],
  "labels": ["^tier:dev$"],
  "run_id": "...",
  "workspace_name": "...",
  "source_repo": "owner/repo"
}
```

caller workflow は 2 通りで消費できる。

**(a) labels を B に中継** (1 invocation で複数 env、B 自身が enumerate+filter):

```yaml
name: Firebase Platform Trigger
on:
  repository_dispatch:
    types: [firebase_platform_requested]

jobs:
  firebase:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: ${{ github.event.client_payload.service }}
          labels: ${{ toJSON(github.event.client_payload.labels) }}
          tfc_org: my-tfc-org
          bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

**(b) environments を matrix で fan-out** (A が解決した env をそのまま使う):

```yaml
name: Firebase Platform Trigger
on:
  repository_dispatch:
    types: [firebase_platform_requested]

jobs:
  firebase:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        env: ${{ fromJSON(github.event.client_payload.environments) }}
    steps:
      - uses: actions/checkout@v4
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: ${{ github.event.client_payload.service }}
          environment: ${{ matrix.env }}
          tfc_org: my-tfc-org
          bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

`labels` が空（A が `environment` 単数指定で呼ばれた場合）は (a) の候補がゼロになる可能性があるので (b) を選ぶ。詳細は [cloud-run-router/README.md](../../cloud-run-router/README.md#dispatch-payload-shape)。

### Workflow 例: labels で複数 env をまとめて再 apply

```yaml
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: my-service
          labels: '["^tier:dev$"]'
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

→ `tier:dev` ラベルが付いた env を順次 dispatch（各 env で workspace upsert + Run を 1 回）。

### Apply Policy

| 値 | 動作 |
|----|------|
| `auto` | 全環境で auto-apply |
| `manual` | 全環境で手動承認 |
| `env-based` (default) | env key が `dev` で始まるもの → auto-apply、その他 → 手動承認 |

全 Inputs / Outputs: [`actions/dispatch-firebase-platform/README.md`](../../actions/dispatch-firebase-platform/README.md)

---

## env の追加・削除フロー

**新規 env を構築する PR**

```yaml
# settings.yml
environments:
  prd-002:        # ← 追加
    status: active
    labels: [tier:prd]
    billing_account_id: "..."
    firebase_platform: { ... }
retained_envs:
  - prd-001
  - prd-002       # ← 本番系は最初から retained_envs にも追加（誤削除ガード）
```

→ Action A / B を順次実行すれば `prd-002` 用のリソースが追加される。

**dev 系を捨てる PR**

```yaml
# settings.yml の environments から削除するだけ
# retained_envs にも書かない
```

→ 次回 Action A 実行で GCP project が destroy、Action B 実行で TFC workspace が force-delete される。

**prd 系を「もう要らない」にする PR**

```yaml
# environments から削除
# retained_envs には残す（誤削除ガード継続）
retained_envs:
  - prd-001
  - prd-002
```

→ 次回 Action A 実行で `removed { destroy = false }` ブロックが生成され、state からだけ外れて GCP リソースは残る。Action B は workspace を残す。後で GCP Console から手動削除する。

---

## Phase 2 Webhook 連携を有効にする

Action A に以下の追加 Inputs を渡すと、TFC Workspace に notification が設定され、Run 完了時に Cloud Run Router 経由で Action B が自動 dispatch されます:

```yaml
enable_webhook_notification: "true"
cloud_run_webhook_url: https://router-xxxxx.run.app/tfc-webhook
cloud_run_webhook_secret: ${{ secrets.WEBHOOK_SECRET }}
```

---

## 次のステップ

→ [Step 4: Cloud Run Router](./04-cloud-run-router.md) — Phase 2 Webhook を使う場合は Cloud Run Router をデプロイします。

→ Phase 1 のみで運用する場合は [Step 5: エンドツーエンド検証](./05-end-to-end.md) へ進んでください。
