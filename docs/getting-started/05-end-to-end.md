# Step 5: エンドツーエンド検証

全コンポーネントが連動して GCP Project 作成 → Firebase Platform 構築まで正常に動作することを検証します。

---

## 前提条件

- [Step 0](./00-billing-account.md)–[Step 4](./04-cloud-run-router.md) が完了済み（Phase 1 の場合は Step 4 をスキップ可）
- テスト用のサービス名・環境キーを決定済み（例: `service=test-app`, env_key=`dev-001`）
  - env_key は `{service}-{env_key}` で GCP project_id の suffix になる規約

---

## Phase 1 (Polling) での検証

### 1. Action A (dispatch-project-bootstrap) の実行

Project Repository の Actions タブから `workflow_dispatch` を実行:

- `service`: `test-app`
- `environment`: `dev-001` （A は単数 `environment` input）

または labels で複数 env をまとめて bootstrap する場合:

- `service`: `test-app`
- `labels`: `'["^tier:dev$"]'`

### 2. TFC Run の確認

TFC UI で `project-factory-test-app` Workspace の Run が作成されていることを確認:

- Plan → Apply が正常に完了すること
- GCP Console で `test-app-dev-001` Project が作成されていること

### 3. Action B (dispatch-firebase-platform) の実行

Phase 1 では Action A 完了後に手動で Action B を実行:

- `service`: `test-app`
- `environments`: `'["dev-001"]'` （B は JSON 配列 `environments` input）

複数 env を一括で扱う場合は `environments: '["dev-001","dev-002"]'` または labels:

- `service`: `test-app`
- `labels`: `'["^tier:dev$"]'`

### 4. Firebase Platform の確認

TFC UI で `test-app-dev-001` Workspace の Run が完了後:

- Firebase Console で `test-app-dev-001` Project が Firebase 化されていること
- 設定した Firebase / GCP サービスが有効化されていること

---

## Phase 2 (Webhook) での検証

### 1. Action A の実行

Phase 1 と同様に `workflow_dispatch` で Action A を実行。ただし `enable_webhook_notification: "true"` で TFC notification が設定されている前提です。

### 2. 自動連鎖の確認

以下が自動的に順次実行されることを確認:

1. **TFC Run (project-factory-test-app)** — Plan → Apply 完了
2. **TFC Notification** → Cloud Run Router へ POST
3. **Cloud Run Router** — HMAC 検証 → run_message を parse → `repository_dispatch` 発火
4. **Action B Workflow** — 自動トリガー（`client_payload.environments` / `labels` を input に渡す）
5. **TFC Run (test-app-dev-001)** — Plan → Apply 完了

### 3. client_payload の中身を確認

Cloud Run Router が発火する `repository_dispatch` の `client_payload` は **hybrid shape**:

```json
{
  "service": "test-app",
  "environments": ["dev-001"],
  "labels": ["^tier:dev$"],
  "run_id": "run-abc",
  "workspace_name": "project-factory-test-app",
  "source_repo": "owner/repo"
}
```

caller workflow は `environments` か `labels` のどちらかを Action B の input に渡す（[Step 3](./03-github-actions.md#workflow-%E4%BE%8B-phase-2-webhook) 参照）。

### 4. ログの確認

- **Cloud Run**: Cloud Logging で Router のログを確認
  - HMAC 検証成功
  - workspace_name のルーティング成功
  - `repository_dispatch` 発火成功（payload に `environments` / `labels` が乗っているか）
- **GitHub Actions**: Action B の Workflow run が `repository_dispatch` でトリガーされていること
- **TFC**: 両 Workspace の Run が正常に完了していること

---

## チェックリスト

| # | 確認項目 | Phase 1 | Phase 2 |
|---|----------|:-------:|:-------:|
| 1 | Action A が正常に実行される | Yes | Yes |
| 2 | `project-factory-{service}` Workspace が作成される | Yes | Yes |
| 3 | TFC Run (project-bootstrap) が Apply 完了する | Yes | Yes |
| 4 | GCP Project (`{service}-{env_key}`) が作成される | Yes | Yes |
| 5 | Cloud Run Router が通知を受信する | — | Yes |
| 6 | run_message が hybrid shape (`environments` + `labels`) で parse される | — | Yes |
| 7 | `repository_dispatch` の `client_payload` に environments / labels が乗る | — | Yes |
| 8 | Action B が自動トリガーされる | — | Yes |
| 9 | Action B が正常に実行される | Yes (手動) | Yes (自動) |
| 10 | `{service}-{env_key}` Workspace が作成される | Yes | Yes |
| 11 | TFC Run (firebase-platform) が Apply 完了する | Yes | Yes |
| 12 | Firebase Console で Project が Firebase 化されている | Yes | Yes |

---

## トラブルシューティング

### Action A が失敗する

- `TFC_TOKEN` secret が正しく設定されているか確認
- `bootstrap_project_number` が数値の Project Number であること（Project ID ではない）
- `parent_organization_id` か `parent_folder_id` のどちらかが指定されていること
- `environment` / `labels` のどちらか少なくとも一方が指定されていること（両方未指定はエラー）

### Action B が失敗する

- `TFC_TOKEN` secret が正しく設定されているか確認
- `environments` の入力 shape が JSON 配列文字列であること（例: `'["dev-001","dev-002"]'`）
- `environments` に指定したキーが settings.yml の `environments:` に存在すること（存在しないと available 一覧と共に error）
- `environments` / `labels` のどちらか少なくとも一方が非空であること

### TFC Run が Plan で失敗する

- Workspace の Environment Variables (`TFC_GCP_PROVIDER_AUTH`, `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL`, `TFC_GCP_WORKLOAD_PROVIDER_NAME`) が正しいか確認
- [docs/project-bootstrap/bootstrap.md](../project-bootstrap/bootstrap.md) のトラブルシューティングを参照

### Cloud Run Router が通知を受信しない (Phase 2)

- TFC Workspace の Notification 設定を確認（URL, Token, Events）
- Cloud Run のログで 4xx/5xx エラーがないか確認
- HMAC secret が TFC Notification と Cloud Run で一致しているか確認

### Cloud Run Router が run_message を parse できない (Phase 2)

- Action A の Run message が hybrid JSON shape (`{"service","environments","labels","source_repo","sha"}`) になっているか確認
- 古い shape (`{"service","env","source_repo"}`) は parse 失敗で reject される
- `METADATA_SOURCE=both` なら TFC API fallback が走るが、A の per-service workspace では `environments` 変数の累積キーが返るため per-Run の精度は落ちる

### Action B がトリガーされない (Phase 2)

- Cloud Run のログで `repository_dispatch` の発火ログを確認（成功 / 失敗どちらか）
- GitHub App の権限に `contents: write` が含まれているか確認
- `DISPATCH_EVENT_TYPE` と caller workflow の `repository_dispatch.types` が一致しているか確認
- caller workflow が `client_payload.environments` を `environments:` (JSON 配列) として渡しているか確認（`environment:` 単数だと無効）

---

## 詳細リファレンス

- [docs/project-bootstrap/architecture.md](../project-bootstrap/architecture.md) — 全体アーキテクチャ
- [docs/project-bootstrap/related-components.md](../project-bootstrap/related-components.md) — 関連コンポーネント
- [cloud-run-router/README.md](../../cloud-run-router/README.md) — Cloud Run Router の詳細
- [actions/dispatch-project-bootstrap/README.md](../../actions/dispatch-project-bootstrap/README.md) — Action A の入出力詳細
- [actions/dispatch-firebase-platform/README.md](../../actions/dispatch-firebase-platform/README.md) — Action B の入出力詳細
