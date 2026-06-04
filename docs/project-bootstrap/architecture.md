# Architecture

GCP Project 作成から Firebase Platform 構築までの全体アーキテクチャ俯瞰。

---

## 全体フロー

```text
01. infra-bootstrap script
  → infra-bootstrap Project
  → terraform-project-factory SA
  → WIF / OIDC

02. project-bootstrap module (terraform-google-project-bootstrap)
  → service/env GCP Project
  → terraform-{service}-{env} SA
  → target Project IAM
  → impersonation IAM

03. terraform-google-firebase-project-platform module
  → Firebase Project 化
  → Firebase / GCP 周辺サービス設定
```

---

## Workspace 構造

| Workspace 名 | 用途 | 使用 Module | SA |
|--------------|------|-------------|-----|
| `project-factory-{service}` | per-service。全 env の Project を累積管理 | `project-bootstrap` | `terraform-project-factory` |
| `{service}-{env}` | per env。Firebase Platform 専用 (terminal) | `terraform-google-firebase-project-platform` | `terraform-{service}-{env}` |

---

## Provisioning 方式

### Phase 1: Polling

```text
Project Repository (settings.yml merge)
  → repository_dispatch
  → infra-orchestrator
    → Workflow A: project-factory Run 起動 → polling → applied 確認
    → Workflow B: firebase-platform Run 起動
```

- GitHub Actions 内で TFC Run の完了を polling で待機
- `infra-orchestrator` (private リポジトリ) が中央集約的に管理

### Phase 2: Webhook

```text
Project Repository (settings.yml merge to env branch)
  → Project Repo Workflow (Action A 使用)
  → Terraform Cloud Run (project-factory-{service})
  → TFC Notification (webhook)
  → Cloud Run router (HMAC verify → routing)
  → GitHub repository_dispatch → Project Repository
  → Project Repo Workflow (Action B 使用)
  → Terraform Cloud Run ({service}-{env})
  → Firebase Project 完成
```

- TFC Run 完了を webhook で検知し、polling 不要
- `infra-orchestrator` への依存なし
- Phase 1 と共存可能 (service 単位で opt-in)

### Phase 1 ↔ Phase 2 共存戦略

| 状態 | Cloud Run router | Project Repo workflow |
|------|------------------|-----------------------|
| Phase 1 only | 未デプロイ | infra-orchestrator 経由 |
| 移行期 | デプロイ済 (service 単位 opt-in) | 混在可 |
| Phase 2 only | デプロイ済 (全 service) | Action A/B 直接 call |

Workspace に notification を設定しない限り Cloud Run router は呼ばれない。notification を後から追加するだけで Phase 1 → Phase 2 移行可能。

---

## Apply 方針

### Workflow A (project-bootstrap)

全環境で **auto-apply**。

理由:

- Project 作成・SA 作成・IAM 設定は冪等で低リスク
- Workflow A → B のチェーンを遅延なく繋ぐ必要がある

### Workflow B (firebase-platform)

環境別に承認ポリシーを分ける:

| 環境 | 方針 |
|------|------|
| `dev` | auto apply |
| `stg` | manual apply recommended |
| `prd` | manual apply required |

---

## Billing Account 戦略

Project Repository は Billing Account ID を知らない。`billing_account_key` のみを指定する。

```yaml
# Project Repository 側
billing_account_key: "{service}-main"
```

実際の `billing_account_id` は infra 側の Billing Account Registry (`configs/billing-accounts.yml`) で解決する。

---

## 状態管理

### Git で管理する値

| 管理先 | 値 |
|--------|-----|
| Project Repository | `service`, `environment`, `project_id`, `billing_account_key`, `firebase_platform` settings |
| Infra Repository | `billing_account_key` → `billing_account_id` mapping, TFC organization/project settings, WIF provider information |

### Git で管理しない値 (Terraform State / API / 決定的命名規則から取得)

`project_number`, `workspace_id`, `run_id`, `service_account_email`, `firebase_app_id`

---

## 関連ドキュメント

- [docs/bootstrap.md](./bootstrap.md) — bootstrap script の実行手順
- [docs/design/iam-policy.md](./design/iam-policy.md) — IAM role 付与の設計根拠
- [docs/design/wif-attribute-mapping.md](./design/wif-attribute-mapping.md) — WIF attribute mapping の詳細
- [docs/related-components.md](./related-components.md) — 関連コンポーネント
- [actions/dispatch-project-bootstrap/README.md](../../actions/dispatch-project-bootstrap/README.md) — Action A の使い方
