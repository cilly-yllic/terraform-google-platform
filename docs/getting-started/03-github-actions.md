# Step 3: GitHub Actions 設定

Project Repository の Workflow で `dispatch-project-bootstrap` (Action A) と `dispatch-firebase-platform` (Action B) を使用する設定を行います。

---

## 前提条件

- [Step 2: TFC セットアップ](./02-tfc-setup.md) が完了済み
- GitHub App が作成済み（`repository_dispatch` 権限を持つもの）
- 以下の GitHub Secrets が設定済み:

| Secret | 説明 |
|--------|------|
| `GH_APP_ID` | GitHub App ID |
| `GH_APP_PRIVATE_KEY` | GitHub App Private Key (PEM) |
| `TFC_TOKEN` | Terraform Cloud API Token |

---

## Action A: dispatch-project-bootstrap

Project Repository の Workflow から Action A を呼び出して GCP Project を作成します。

### Workflow 例

```yaml
name: Project Bootstrap
on:
  workflow_dispatch:
    inputs:
      service:
        required: true
      environment:
        required: true
        type: choice
        options: [dev, stg, prd]

jobs:
  bootstrap:
    runs-on: ubuntu-latest
    steps:
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-project-bootstrap@main
        with:
          service: ${{ inputs.service }}
          environment: ${{ inputs.environment }}
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          billing_registry_repo: my-org/infra
          github_app_id: ${{ secrets.GH_APP_ID }}
          github_app_private_key: ${{ secrets.GH_APP_PRIVATE_KEY }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

### 主要 Inputs

| Input | 説明 |
|-------|------|
| `service` | サービス名 |
| `environment` | 対象環境 (`dev` / `stg` / `prd`) |
| `tfc_org` | Terraform Cloud Organization 名 |
| `bootstrap_project_number` | Bootstrap Project の数値 ID（WIF リソース名に使用） |
| `billing_registry_repo` | `billing-accounts.yml` を管理する `owner/repo` |
| `labels` | (任意) JSON 配列の RegExp。env の `labels` が全パターンに AND 一致しない場合は success-skip |

全 Inputs の詳細: [`actions/dispatch-project-bootstrap/README.md`](../../actions/dispatch-project-bootstrap/README.md)

> **Tip — env のゲーティング**: settings.yml の `environments.<env>.status: inactive` を指定した env や、Action input `labels` の RegExp に一致しない env は `outputs.skipped="true"` で success-skip される。matrix で全 env をループしながら絞り込む用途に便利。詳細は [Environment gating](../../actions/dispatch-project-bootstrap/README.md#environment-gating)。

---

## Action B: dispatch-firebase-platform

Action A で作成された Project に対し、Firebase Platform リソースを構築します。

### Phase 1 (Polling) の場合

Action A 完了後に手動または infra-orchestrator 経由で呼び出します。

### Phase 2 (Webhook) の場合

Cloud Run Router からの `repository_dispatch` で自動的にトリガーされます（[Step 4](./04-cloud-run-router.md) を参照）。

### Workflow 例 (Phase 2: repository_dispatch トリガー)

```yaml
name: Firebase Platform
on:
  repository_dispatch:
    types: [firebase_platform_requested]

jobs:
  firebase:
    runs-on: ubuntu-latest
    steps:
      - uses: cilly-yllic/terraform-google-platform/actions/dispatch-firebase-platform@main
        with:
          service: ${{ github.event.client_payload.service }}
          environment: ${{ github.event.client_payload.environment }}
          tfc_org: my-tfc-org
          bootstrap_project_number: "123456789012"
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

### Apply Policy

| 値 | 動作 |
|----|------|
| `auto` | 全環境で auto-apply |
| `manual` | 全環境で手動承認 |
| `env-based` (default) | dev = auto-apply, stg/prd = 手動承認 |

### Env のゲーティング

Action A と同様、`environments.<env>.status: inactive` や Action input `labels` (JSON 配列の RegExp) によって env 単位で success-skip させられる。詳細は [Environment gating](../../actions/dispatch-firebase-platform/README.md#environment-gating)。

全 Inputs の詳細: [`actions/dispatch-firebase-platform/README.md`](../../actions/dispatch-firebase-platform/README.md)

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
