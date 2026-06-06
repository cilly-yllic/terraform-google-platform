# Step 5: エンドツーエンド検証

全コンポーネントが連動して GCP Project 作成 → Firebase Platform 構築まで正常に動作することを検証します。

---

## 前提条件

- [Step 0](./00-billing-account.md)–[Step 4](./04-cloud-run-router.md) が完了済み（Phase 1 の場合は Step 4 をスキップ可）
- テスト用のサービス名・環境名を決定済み（例: `service=test-app`, `environment=dev`）

---

## Phase 1 (Polling) での検証

### 1. Action A (dispatch-project-bootstrap) の実行

Project Repository の Actions タブから `workflow_dispatch` を実行:

- `service`: `test-app`
- `environment`: `dev`

### 2. TFC Run の確認

TFC UI で `project-factory-test-app` Workspace の Run が作成されていることを確認:

- Plan → Apply が正常に完了すること
- GCP Console で `test-app-dev` Project が作成されていること

### 3. Action B (dispatch-firebase-platform) の実行

Phase 1 では Action A 完了後に手動で Action B を実行:

- `service`: `test-app`
- `environment`: `dev`

### 4. Firebase Platform の確認

TFC UI で `test-app-dev` Workspace の Run が完了後:

- Firebase Console で `test-app-dev` Project が Firebase 化されていること
- 設定した Firebase / GCP サービスが有効化されていること

---

## Phase 2 (Webhook) での検証

### 1. Action A の実行

Phase 1 と同様に `workflow_dispatch` で Action A を実行。ただし webhook が有効化されている前提です。

### 2. 自動連鎖の確認

以下が自動的に順次実行されることを確認:

1. **TFC Run (project-factory-test-app)** — Plan → Apply 完了
2. **TFC Notification** → Cloud Run Router へ POST
3. **Cloud Run Router** — HMAC 検証 → `repository_dispatch` 発火
4. **Action B Workflow** — 自動トリガー
5. **TFC Run (test-app-dev)** — Plan → Apply 完了

### 3. ログの確認

- **Cloud Run**: Cloud Logging で Router のログを確認
  - HMAC 検証成功
  - workspace_name のルーティング成功
  - `repository_dispatch` 発火成功
- **GitHub Actions**: Action B の Workflow run が `repository_dispatch` でトリガーされていること
- **TFC**: 両 Workspace の Run が正常に完了していること

---

## チェックリスト

| # | 確認項目 | Phase 1 | Phase 2 |
|---|----------|:-------:|:-------:|
| 1 | Action A が正常に実行される | Yes | Yes |
| 2 | `project-factory-{service}` Workspace が作成される | Yes | Yes |
| 3 | TFC Run (project-bootstrap) が Apply 完了する | Yes | Yes |
| 4 | GCP Project が作成される | Yes | Yes |
| 5 | Cloud Run Router が通知を受信する | — | Yes |
| 6 | `repository_dispatch` が発火される | — | Yes |
| 7 | Action B が自動トリガーされる | — | Yes |
| 8 | Action B が正常に実行される | Yes (手動) | Yes (自動) |
| 9 | `{service}-{env}` Workspace が作成される | Yes | Yes |
| 10 | TFC Run (firebase-platform) が Apply 完了する | Yes | Yes |
| 11 | Firebase Console で Project が Firebase 化されている | Yes | Yes |

---

## トラブルシューティング

### Action A が失敗する

- GitHub Secrets (`GH_APP_ID`, `GH_APP_PRIVATE_KEY`, `TFC_TOKEN`) が正しく設定されているか確認
- `bootstrap_project_number` が数値の Project Number であること（Project ID ではない）
- `billing_registry_repo` のフォーマットが `owner/repo` であること

### TFC Run が Plan で失敗する

- Workspace の Environment Variables (`TFC_GCP_PROVIDER_AUTH`, `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL`, `TFC_GCP_WORKLOAD_PROVIDER_NAME`) が正しいか確認
- [docs/project-bootstrap/bootstrap.md](../project-bootstrap/bootstrap.md) のトラブルシューティングを参照

### Cloud Run Router が通知を受信しない (Phase 2)

- TFC Workspace の Notification 設定を確認（URL, Token, Events）
- Cloud Run のログで 4xx/5xx エラーがないか確認
- HMAC secret が TFC Notification と Cloud Run で一致しているか確認

### Action B がトリガーされない (Phase 2)

- Cloud Run のログで `repository_dispatch` の発火ログを確認
- GitHub App の権限に `contents: write` が含まれているか確認
- `DISPATCH_EVENT_TYPE` と Workflow の `repository_dispatch.types` が一致しているか確認

---

## 詳細リファレンス

- [docs/project-bootstrap/architecture.md](../project-bootstrap/architecture.md) — 全体アーキテクチャ
- [docs/project-bootstrap/related-components.md](../project-bootstrap/related-components.md) — 関連コンポーネント
- [cloud-run-router/README.md](../../cloud-run-router/README.md) — Cloud Run Router の詳細
