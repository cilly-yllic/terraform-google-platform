# Step 4: Cloud Run Router のデプロイ

Phase 2 (Webhook) アーキテクチャを使用する場合、Cloud Run Router をデプロイし TFC Notification を設定します。

> **Note**: Phase 1 (Polling) のみで運用する場合はこの Step をスキップし、[Step 5: エンドツーエンド検証](./05-end-to-end.md) へ進んでください。

---

## 概要

Cloud Run Router は TFC の Run 完了通知を受信し、GitHub `repository_dispatch` を発火するサービスです。

```text
TFC Workspace (project-factory-{service})
  ↓ Run applied
  ↓ TFC Notification (HTTP POST + HMAC-SHA512)
Cloud Run Router (/webhook)
  ↓ HMAC verify → workspace_name routing → metadata parse
GitHub repository_dispatch → Project Repository
  ↓ firebase_platform_requested event
Action B Workflow → Firebase Platform Workspace Run
```

---

## 前提条件

- GCP Project（Cloud Run をデプロイする先）
- `gcloud` CLI + 認証済み
- GitHub App（`repository_dispatch` 権限）

---

## 手順

### 1. Secret Manager にシークレットを格納

以下の値を GCP Secret Manager に格納します:

| Secret 名 | 説明 |
|-----------|------|
| `tfc-notification-secret` | TFC Notification との HMAC 共有 secret |
| `github-app-private-key` | GitHub App Private Key (PEM) |
| `tfc-api-token` | TFC API Token（Option A / both 使用時） |

### 2. Cloud Run へデプロイ

```bash
cd cloud-run-router

gcloud run deploy cloud-run-router \
  --source . \
  --region asia-northeast1 \
  --set-env-vars "GITHUB_APP_ID=<app-id>" \
  --set-secrets "TFC_NOTIFICATION_SECRET=tfc-notification-secret:latest,GITHUB_APP_PRIVATE_KEY=github-app-private-key:latest,TFC_API_TOKEN=tfc-api-token:latest" \
  --allow-unauthenticated
```

> `--allow-unauthenticated` は TFC からの webhook を受信するために必要です。HMAC-SHA512 署名検証でセキュリティを確保しています。

デプロイ後、Cloud Run の URL を控えてください（例: `https://cloud-run-router-xxxxx.run.app`）。

### 3. 環境変数の確認

| 変数 | デフォルト | 説明 |
|------|-----------|------|
| `PORT` | `8080` | HTTP リスニングポート |
| `WORKSPACE_NAME_PATTERN` | `^project-factory-(?<service>.+)$` | project-factory stage の workspace 名 regex |
| `TERMINAL_WORKSPACE_PATTERN` | `^(?<service>.+)-(?<env>[^-]+)$` | terminal stage の workspace 名 regex |
| `DISPATCH_EVENT_TYPE` | `firebase_platform_requested` | `repository_dispatch` の event_type |
| `METADATA_SOURCE` | `both` | metadata 解析: `run_message` / `run_variables` / `both` |

### 4. TFC Notification の設定

TFC の project-factory Workspace に Notification を追加します:

1. TFC UI → Workspace Settings → Notifications
2. **Destination**: Webhook
3. **URL**: `https://<cloud-run-url>/webhook`
4. **Token**: Secret Manager に格納した HMAC secret と同じ値
5. **Events**: "Completed" を選択

または、[Step 3](./03-github-actions.md) で説明した通り Action A の `enable_webhook_notification` を使えば自動設定されます。

### 5. 動作確認

```bash
# ヘルスチェック
curl https://<cloud-run-url>/healthz
```

`OK` が返ればデプロイ成功です。

---

## 次のステップ

→ [Step 5: エンドツーエンド検証](./05-end-to-end.md) — 全コンポーネントを通した検証を行います。

---

## 詳細リファレンス

- [cloud-run-router/README.md](../../cloud-run-router/README.md)
- [docs/project-bootstrap/architecture.md](../project-bootstrap/architecture.md)
