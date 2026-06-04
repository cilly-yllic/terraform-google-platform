# Related Components

本リポジトリの外にある関連コンポーネントの概要と責務。詳細な仕様はそれぞれのリポジトリを参照。

---

## terraform-google-firebase-project-platform

**リポジトリ:** [MoooDoNE/terraform-google-firebase-project-platform](https://github.com/MoooDoNE/terraform-google-firebase-project-platform)

公開 Terraform Registry Module。`terraform-gcp-project-factory` で作成した GCP Project を Firebase Platform として初期化し、Firebase および関連 GCP サービスを管理する。

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

**配置:** [`terraform-google-firebase-project-platform/cloud-run-router/`](https://github.com/MoooDoNE/terraform-google-firebase-project-platform/tree/main/cloud-run-router)

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

### Action A: dispatch-tfc-project-factory

**配置:** 本リポジトリ [`actions/dispatch/`](../actions/dispatch/)

`settings.yml` + branch 由来の env → Project Factory Run 起動。

詳細: [actions/dispatch/README.md](../actions/dispatch/README.md)

### Action B: dispatch-tfc-firebase-platform

**配置:** [`terraform-google-firebase-project-platform/actions/dispatch/`](https://github.com/MoooDoNE/terraform-google-firebase-project-platform/tree/main/actions/dispatch)

`settings.yml` + project-factory outputs → Firebase Platform Run 起動。

詳細: [terraform-google-firebase-project-platform/actions/dispatch/README.md](https://github.com/MoooDoNE/terraform-google-firebase-project-platform/blob/main/actions/dispatch/README.md)
