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

## デプロイ方式の選択

| 方式 | いつ使うか |
|------|----------|
| **A. GitHub Actions + WIF (推奨)** | 通常運用 — タグベース、監査ログあり、Slack 通知 |
| B. `gcloud run deploy` (手動) | 緊急 hotfix / ローカル検証 / 初回の動作確認 |

A. は **private な deploy 用 repo に workflow を置く**設計が推奨です (理由: cloud-run-router のソースコードを置く本リポジトリは公開なので、deploy 権限の隔離が必要)。

---

## 方式 A: GitHub Actions + Workload Identity Federation (推奨)

### A-1. bootstrap script を opt-in モードで再実行

`scripts/bootstrap.sh` を `ENABLE_CLOUD_RUN_DEPLOY_SETUP=true` で動かすと、Cloud Run deploy 用の SA / WIF Provider が一括で provision されます。

```bash
# .env に追記
cat >> .env <<'ENV'
ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"
GITHUB_REPOSITORY="<your-org>/<your-deploy-repo>"   # ← deploy workflow を置く private repo
ENV

# 既存リソース skip + 新規追加
make bootstrap

# GitHub Variables 用の値を出力
make bootstrap-print-env
```

作成されるもの:
- runtime SA (`cloud-run-router-runtime`) — `roles/secretmanager.secretAccessor` のみ
- deploy SA (`cloud-run-router-deploy`) — Cloud Run / Artifact Registry / Cloud Build 等の必要 role
- GitHub WIF Provider — `assertion.repository == "<your-org>/<your-deploy-repo>"` で deploy repo に絞る
- 追加 API enable (run / artifactregistry / cloudbuild / secretmanager)

詳細: [`scripts/README.md` — Cloud Run router deploy 拡張](../../scripts/README.md#cloud-run-router-deploy-拡張-opt-in)

### A-2. private deploy repo に workflow を配置

[`examples/cloud-run-router-deploy/deploy-cloud-run-router.yml`](../../examples/cloud-run-router-deploy/deploy-cloud-run-router.yml) を deploy 用 private repo の `.github/workflows/deploy-cloud-run-router.yml` にコピー。

詳しい配置手順 / Variables・Secrets の登録方法 / Secret Manager のセットアップは:
→ [`examples/cloud-run-router-deploy/README.md`](../../examples/cloud-run-router-deploy/README.md)

### A-3. runtime secret の登録 (GitHub Secrets が single source of truth)

方式 A では Secret Manager への**値の投入は deploy workflow が自動で行う**ため、`gcloud secrets create` を手で叩く必要はありません。Secret Manager の空 container (`tfc-notification-secret` / `github-app-private-key`) は A-1 の `make bootstrap` で作成済みです。値の流れは次の通り:

- **`TFC_NOTIFICATION_SECRET`** (HMAC 共有 secret): `init-router-hmac.yml` workflow を `rotate=false` で実行すると `openssl rand -hex 32` で生成され、deploy repo の Repository Secret に登録されます。値は **TFC 側の Notification 設定の Token と一致** させる必要がありますが、Action A の `enable_webhook_notification` 経由で Notification を作る場合はこの GitHub Secret が両者の single source of truth になります。
- **`GH_APP_PRIVATE_KEY`** (GitHub App PEM): GitHub App 設定画面で生成した `.pem` を deploy repo の Repository Secret に手動登録します。

deploy workflow は実行のたびにこの 2 つの GitHub Secrets を Secret Manager へ sync (`gcloud secrets versions add`) し、新しい Cloud Run revision が `:latest` を読みます。詳細な登録手順は [`examples/cloud-run-router-deploy/README.md`](../../examples/cloud-run-router-deploy/README.md) の Step 4〜6 を参照してください。

> Option A / `both` モード (`METADATA_SOURCE`) を使う場合は `tfc-api-token` container を別途作成し、deploy workflow の `--set-secrets` に `TFC_API_TOKEN=tfc-api-token:latest` を追記してください。

### A-4. deploy workflow を起動

`init-router-hmac.yml` を `rotate=false` で実行して `TFC_NOTIFICATION_SECRET` を初期化すると、**deploy workflow (`Deploy cloud-run-router`) が `workflow_run` trigger で自動起動**します (tag 入力は廃止済み。常に source repo の main HEAD を build & deploy します)。

source repo の main に新しい commit を反映したいときは、private deploy repo の **Actions → "Deploy cloud-run-router" → Run workflow** で手動起動します。完了すると Slack に Cloud Run URL と `/webhook` endpoint URL が通知され、`CLOUD_RUN_WEBHOOK_URL` Repository Secret に自動登録されます。

---

## 方式 B: `gcloud run deploy` (手動 fallback)

bootstrap の opt-in セットアップが済んでいれば runtime SA を流用できます:

```bash
cd cloud-run-router

gcloud run deploy cloud-run-router \
  --source . \
  --region asia-northeast1 \
  --service-account cloud-run-router-runtime@<BOOTSTRAP_PROJECT_ID>.iam.gserviceaccount.com \
  --set-env-vars "GITHUB_APP_ID=<app-id>,METADATA_SOURCE=run_message,DISPATCH_EVENT_TYPE=firebase_platform_requested" \
  --set-secrets "TFC_NOTIFICATION_SECRET=tfc-notification-secret:latest,GITHUB_APP_PRIVATE_KEY=github-app-private-key:latest" \
  --allow-unauthenticated
```

> `--allow-unauthenticated` は TFC からの webhook を受信するために必要です。HMAC-SHA512 署名検証でセキュリティを確保しています。
>
> `METADATA_SOURCE` を省略すると default は `both` になり `TFC_API_TOKEN` が必須です（未設定だと起動時に fail fast で落ちます）。TFC API を使わない構成では上記のように `run_message` を明示してください。

deploy 後、Cloud Run の URL を控えてください (例: `https://cloud-run-router-xxxxx.run.app`)。

---

## 環境変数リファレンス

Cloud Run service の runtime で参照される環境変数:

| 変数 | 必須/任意 | デフォルト | 説明 |
|------|---------|-----------|------|
| `PORT` | 任意 | `8080` | HTTP リスニングポート (Cloud Run が指定) |
| `TFC_NOTIFICATION_SECRET` | 必須 | — | TFC Notification の HMAC-SHA512 共有 secret |
| `GITHUB_APP_ID` | 必須 | — | GitHub App ID (数値) |
| `GITHUB_APP_PRIVATE_KEY` | 必須 | — | GitHub App Private Key (PEM 文字列) |
| `TFC_API_TOKEN` | 条件付き | — | `METADATA_SOURCE=run_variables` / `both` で必須 |
| `TFC_API_BASE_URL` | 任意 | `https://app.terraform.io` | TFE 自社運用時に上書き |
| `WORKSPACE_NAME_PATTERN` | 任意 | `^project-factory-(?<service>.+)$` | project-factory stage の workspace 名 regex |
| `TERMINAL_WORKSPACE_PATTERN` | 任意 | `^(?<service>.+)-(?<env>[^-]+)$` | terminal stage の workspace 名 regex |
| `DISPATCH_EVENT_TYPE` | 任意 | `firebase_platform_requested` | repository_dispatch の event_type |
| `METADATA_SOURCE` | 任意 | `both` | `run_message` / `run_variables` / `both` |

---

## TFC Notification の設定

TFC の project-factory Workspace に Notification を追加します:

1. TFC UI → Workspace Settings → Notifications
2. **Destination**: Webhook
3. **URL**: `https://<cloud-run-url>/webhook`
4. **Token**: Secret Manager に格納した HMAC secret と同じ値
5. **Events**: "Completed" を選択

または、[Step 3](./03-github-actions.md) で説明した通り Action A の `enable_webhook_notification` を使えば自動設定されます。

---

## 動作確認

```bash
# ヘルスチェック
curl https://<cloud-run-url>/healthz
# → {"status":"ok"}
```

`{"status":"ok"}` が返ればデプロイ成功です。

---

## 次のステップ

→ [Step 5: エンドツーエンド検証](./05-end-to-end.md) — 全コンポーネントを通した検証を行います。

---

## 詳細リファレンス

- [cloud-run-router/README.md](../../cloud-run-router/README.md) — service 仕様と Deployment セクション
- [examples/cloud-run-router-deploy/README.md](../../examples/cloud-run-router-deploy/README.md) — reference workflow と詳細セットアップ手順
- [scripts/README.md](../../scripts/README.md#cloud-run-router-deploy-拡張-opt-in) — bootstrap opt-in 拡張の中身
- [docs/project-bootstrap/bootstrap.md](../project-bootstrap/bootstrap.md) — bootstrap script 全体のガイド
