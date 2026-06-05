# Related Components

本リポジトリの外にある関連コンポーネントの概要と責務。詳細な仕様はそれぞれのリポジトリを参照。

---

## terraform-google-firebase-project-platform

> **Note**: 旧リポジトリ `cilly-yllic/terraform-google-firebase-project-platform` は本リポジトリに統合済みです。

**パス:** [`modules/firebase-project-platform/`](../../modules/firebase-project-platform/)

公開 Terraform Registry Module。`project-bootstrap` で作成した GCP Project を Firebase Platform として初期化し、Firebase および関連 GCP サービスを管理する。

責務:

- Firebase Project 化
- Firestore / Storage / Hosting / App Hosting / Data Connect 等のリソース作成
- API 自動判定・有効化
- Firebase/GCP 関連 IAM
- CI deploy 用 Service Account の自動 role 付与

同梱 reference 実装:

- `cloud-run-router/` — TFC notification → GitHub repository_dispatch (Phase 2 webhook の中核)
- `actions/dispatch/` — Action B: `{service}-{env}` workspace upsert + Run 起動

---

## infra-orchestrator

Private リポジトリ。Phase 1 (polling) アーキテクチャの中核。

責務:

- Project Repository の `terraform/settings.yml` 取得・検証
- `billing_account_key` → `billing_account_id` 解決
- Terraform Cloud Workspace 作成・更新
- Variables / Environment Variables 同期
- TFC Run 起動・polling・outputs 取得
- 後続 Workflow dispatch

Phase 2 (webhook) への移行により、infra-orchestrator の多くの責務は Action A / Action B + Cloud Run router に移行可能。

---

## Cloud Run router

**配置:** 本リポジトリ [`cloud-run-router/`](../../cloud-run-router/)

Phase 2 webhook アーキテクチャの routing primitive。

責務:

- TFC notification 受信 (HMAC-SHA512 署名検証)
- workspace_name パターンマッチによる stage 判定
- `(service, env, source_repo)` の特定
- GitHub repository_dispatch 発火

非対象:

- TFC Run の起動・キャンセル
- TFC Workspace の作成・削除・Variable 更新
- Terraform state の直接読み書き
- billing-accounts.yml の参照

---

## Public GitHub Actions

### Action A: dispatch-tfc-project-bootstrap

**配置:** 本リポジトリ [`actions/dispatch-project-bootstrap/`](../../actions/dispatch-project-bootstrap/)

`settings.yml` + branch 由来の env → Project Bootstrap Run 起動。

詳細: [actions/dispatch-project-bootstrap/README.md](../../actions/dispatch-project-bootstrap/README.md)

### Action B: dispatch-tfc-firebase-platform

**配置:** 本リポジトリ [`actions/dispatch-firebase-platform/`](../../actions/dispatch-firebase-platform/)

`settings.yml` + project-factory outputs → Firebase Platform Run 起動。

詳細: [actions/dispatch-firebase-platform/README.md](../../actions/dispatch-firebase-platform/README.md)
