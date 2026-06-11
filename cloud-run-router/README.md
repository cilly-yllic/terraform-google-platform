# cloud-run-router

A **reference implementation** of a Cloud Run service that receives Terraform Cloud (TFC) Run completion notifications and fires GitHub `repository_dispatch`.

The core component of the Phase 2 (webhook-driven) architecture. For its position in the overall architecture, see [`docs/architecture.md`](../docs/architecture.md).

> **Related docs**: [architecture.md](../docs/project-bootstrap/architecture.md) / [related-components.md](../docs/project-bootstrap/related-components.md)

<details><summary>Ja</summary>

TFC (Terraform Cloud) Run completion notification を受信し、GitHub `repository_dispatch` を発火する Cloud Run service の **reference implementation**。

> **関連ドキュメント**: [architecture.md](../docs/project-bootstrap/architecture.md) / [related-components.md](../docs/project-bootstrap/related-components.md)

Phase 2 (webhook-driven) アーキテクチャの中核コンポーネント。全体アーキテクチャ上の位置づけは [`docs/architecture.md`](../docs/architecture.md) を参照。

</details>

---

## Architecture overview

```text
TFC Workspace (project-factory-{service})
  ↓ Run applied
  ↓ TFC Notification (HTTP POST + HMAC-SHA512)
  ↓
Cloud Run router (/webhook)
  ↓ HMAC verify → workspace_name routing → metadata parse
  ↓
GitHub repository_dispatch → Project Repository
  ↓ firebase_platform_requested event
  ↓
Action B Workflow → Firebase Platform Workspace Run
```

---

## Features

- **HMAC-SHA512 signature verification** (`X-TFE-Notification-Signature`)
- **workspace_name pattern routing** (regex-based, configurable via env vars)
- **metadata parsing** (Option A: TFC API / Option B: run_message JSON / both)
- **GitHub App authentication** + `repository_dispatch` firing
- **Cloud Logging**-aware structured JSON logs
- **Health check** (`GET /healthz`)

<details><summary>Ja</summary>

- **HMAC-SHA512 署名検証** (`X-TFE-Notification-Signature`)
- **workspace_name パターンルーティング** (regex ベース、環境変数で設定可能)
- **metadata 解析** (Option A: TFC API / Option B: run_message JSON / 両対応)
- **GitHub App 認証** + `repository_dispatch` 発火
- **Cloud Logging** 対応の構造化 JSON ログ
- **ヘルスチェック** (`GET /healthz`)

</details>

---

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/webhook` | Receive TFC notifications |
| `GET` | `/healthz` | Health check |

---

## Environment variables

### Required

| Name | Description |
|------|-------------|
| `TFC_NOTIFICATION_SECRET` | HMAC shared secret with TFC notifications |
| `GITHUB_APP_ID` | GitHub App ID |
| `GITHUB_APP_PRIVATE_KEY` | GitHub App private key (PEM) |

### Optional

| Name | Default | Description |
|------|---------|-------------|
| `PORT` | `8080` | HTTP listening port |
| `TFC_API_TOKEN` | — | TFC API token (required for Option A / both) |
| `TFC_API_BASE_URL` | `https://app.terraform.io` | TFC API base URL |
| `WORKSPACE_NAME_PATTERN` | `^project-factory-(?<service>.+)$` | Regex for the project-factory stage workspace name (named group `service` required) |
| `TERMINAL_WORKSPACE_PATTERN` | `^(?<service>.+)-(?<env>[^-]+)$` | Regex for the terminal stage workspace name (env = last segment) |
| `DISPATCH_EVENT_TYPE` | `firebase_platform_requested` | `repository_dispatch` event_type |
| `METADATA_SOURCE` | `both` | Metadata parsing: `run_message` / `run_variables` / `both` |

### Secret design

Store these in Secret Manager and pass them to Cloud Run as env vars or volume mounts:

- `TFC_NOTIFICATION_SECRET` — HMAC shared secret
- `GITHUB_APP_PRIVATE_KEY` — GitHub App private key (PEM)
- `TFC_API_TOKEN` — TFC API token (when using Option A)

<details><summary>Ja</summary>

### 必須

- `TFC_NOTIFICATION_SECRET` — TFC Notification の HMAC 共有 secret
- `GITHUB_APP_ID` — GitHub App ID
- `GITHUB_APP_PRIVATE_KEY` — GitHub App private key (PEM 形式)

### オプション

- `PORT` (default `8080`) — HTTP リスニングポート
- `TFC_API_TOKEN` — TFC API token (Option A / both 使用時に必要)
- `TFC_API_BASE_URL` (default `https://app.terraform.io`) — TFC API base URL
- `WORKSPACE_NAME_PATTERN` (default `^project-factory-(?<service>.+)$`) — project-factory stage の workspace 名 regex (named group `service` 必須)
- `TERMINAL_WORKSPACE_PATTERN` (default `^(?<service>.+)-(?<env>[^-]+)$`) — terminal stage の workspace 名 regex (env = 最後のセグメント)
- `DISPATCH_EVENT_TYPE` (default `firebase_platform_requested`) — repository_dispatch の event_type
- `METADATA_SOURCE` (default `both`) — metadata 解析方法: `run_message` / `run_variables` / `both`

### Secret 設計

Secret Manager に以下を格納し、Cloud Run に環境変数またはボリュームマウントで渡す:

- `TFC_NOTIFICATION_SECRET` — HMAC 共有 secret
- `GITHUB_APP_PRIVATE_KEY` — GitHub App private key (PEM)
- `TFC_API_TOKEN` — TFC API token (Option A 使用時)

</details>

---

## Metadata parsing

Action A / B が emit する `run_message` の shape は **hybrid**:

```json
{
  "service": "my-svc",
  "environments": ["dev-001", "dev-002"],
  "labels": ["^tier:dev$"],
  "source_repo": "owner/repo",
  "sha": "..."
}
```

- `environments`: Action A が今回 Run で実際に処理した env キーのリスト（解決済み）
- `labels`: Action A 起動時に渡された input labels (RegExp 文字列の配列)。`environment` 単数指定時は空配列

### Option B: `run_message` (推奨)

`run_message` を JSON として直接 parse する。Action A / B どちらの Run でも新 shape が emit されるので、Phase 2 chaining では基本これを使う。

### Option A: `run_variables` (TFC API、フォールバック)

`run_message` が無い・壊れている場合のフォールバックとして TFC API でワークスペース変数を引く。Action A の per-service workspace では `service` (workspace 変数) と `environments` (JSON map 変数の keys) を取り出す。

> **注意**: Action A の workspace の `environments` 変数は管理対象 env を**累積**で保持するため、TFC API 経由で得られる `environments` 配列は「今回の Run の対象 env」ではなく「ワークスペースが管理する全 env」になる。正確な per-Run の env リストが欲しい場合は `run_message` を使うこと。`labels` は workspace 変数からは復元できないため常に空配列が返る。

### `both` (default)

`run_message` を先に試行し、parse 失敗時に TFC API にフォールバック。

<details><summary>Ja</summary>

`run_message` shape (Action A / B が emit):

```json
{
  "service": "my-svc",
  "environments": ["dev-001"],
  "labels": ["^tier:dev$"],
  "source_repo": "owner/repo",
  "sha": "..."
}
```

- `environments`: 今回 Run で処理した env キー（解決済みリスト）
- `labels`: A 起動時の input labels。単数指定時は空配列

#### Option B: `run_message` (推奨)

JSON として直接 parse。新 shape は Action A / B 両方で emit される。

#### Option A: `run_variables` (フォールバック)

TFC API で workspace 変数を引く。Action A のワークスペースなら `service` + `environments` map の keys を使う。`environments` は累積管理されている点に注意（今回 Run の対象とは限らない）。`labels` は復元不能のため空配列。

#### `both` (デフォルト)

`run_message` 先行 → parse 失敗で TFC API にフォールバック。

</details>

---

## Dispatch payload shape

Router は GitHub `repository_dispatch` の `client_payload` に以下の shape を送る:

```json
{
  "service": "my-svc",
  "environments": ["dev-001", "dev-002"],
  "labels": ["^tier:dev$"],
  "run_id": "run-abc",
  "workspace_name": "project-factory-my-svc",
  "source_repo": "owner/repo"
}
```

caller workflow は **2 通り**の消費方法を選べる:

### (a) labels を Action B にそのまま渡す（1 invocation で複数 env）

```yaml
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
          labels: ${{ toJSON(github.event.client_payload.labels) }}
          tfc_org: my-tfc-org
          bootstrap_project_number: ${{ secrets.BOOTSTRAP_PROJECT_NUMBER }}
          tfc_token: ${{ secrets.TFC_TOKEN }}
```

Action B 自身が settings.yml を読み直して enumerate + filter する。`environments` 入力ミスや settings.yml ドリフトに対しても自己整合。

### (b) environments を matrix で fan-out（1 dispatch で per-env 並列）

```yaml
on:
  repository_dispatch:
    types: [firebase_platform_requested]
jobs:
  dispatch:
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

A が解決した env リストを faithfull に再現したい場合（settings.yml drift を許容しない）はこちら。

`labels` が空（A が単数 `environment` で呼ばれていた場合）は (a) が候補ゼロになる可能性があるので (b) を選ぶ。

---

## Local development

```bash
# install deps
npm install

# run dev server (tsx)
export TFC_NOTIFICATION_SECRET=dev-secret
export GITHUB_APP_ID=123456
export GITHUB_APP_PRIVATE_KEY="$(cat /path/to/private-key.pem)"
npm run dev

# tests
npm test

# typecheck
npm run lint

# build
npm run build
npm start
```

---

## Deployment

The `deploy/` directory is `.gitignore`d; users configure it for their own organization.

<details><summary>Ja</summary>

`deploy/` ディレクトリは `.gitignore` で除外されており、利用者が自組織に合わせて構成する。

</details>

### 1. Dockerfile (example)

```dockerfile
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY src/ src/
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY --from=builder /app/dist dist/
COPY --from=builder /app/package*.json ./
# No runtime dependencies — only Node.js built-ins are used
ENV NODE_ENV=production
EXPOSE 8080
CMD ["node", "dist/index.js"]
```

### 2. Cloud Run deploy (gcloud)

```bash
# build & push
gcloud builds submit --tag gcr.io/${PROJECT_ID}/cloud-run-router

# deploy
gcloud run deploy cloud-run-router \
  --image gcr.io/${PROJECT_ID}/cloud-run-router \
  --region asia-northeast1 \
  --platform managed \
  --allow-unauthenticated \
  --set-secrets "TFC_NOTIFICATION_SECRET=tfc-notification-secret:latest,GITHUB_APP_PRIVATE_KEY=github-app-private-key:latest" \
  --set-env-vars "GITHUB_APP_ID=${GITHUB_APP_ID},DISPATCH_EVENT_TYPE=firebase_platform_requested"
```

### 3. TFC notification setup

Add a Notification to each `project-factory-{service}` Workspace:

- **Destination URL**: The Cloud Run service's HTTPS URL + `/webhook`
- **Token**: Same value as `TFC_NOTIFICATION_SECRET`
- **Triggers**: `run:completed`

<details><summary>Ja</summary>

各 `project-factory-{service}` Workspace に Notification を追加:

- **Destination URL**: Cloud Run service の HTTPS URL + `/webhook`
- **Token**: `TFC_NOTIFICATION_SECRET` と同じ値
- **Triggers**: `run:completed`

</details>

### 4. Minimal permissions for the Cloud Run SA

- Secret Manager Secret Accessor (`roles/secretmanager.secretAccessor`)
- No other GCP permissions needed (the GitHub API / TFC API authenticate with their own tokens)

<details><summary>Ja</summary>

- Secret Manager Secret Accessor (`roles/secretmanager.secretAccessor`)
- 他の GCP 権限は不要 (GitHub API / TFC API はそれぞれのトークンで認証)

</details>

---

## Security

- **HMAC verification required**: The `X-TFE-Notification-Signature` header is verified against the body with HMAC-SHA512. Mismatches return `401`.
- **GitHub App credentials**: Provided to Cloud Run via Secret Manager.
- **Cloud Run SA**: Least privilege (Secret Manager accessor only).
- **(Recommended) Cloud Armor**: Allowlist TFC's outbound IPs.
- **Structured logs**: Every request is recorded to Cloud Logging (run_id, workspace_name, dispatch target, result).

<details><summary>Ja</summary>

- **HMAC 検証必須**: `X-TFE-Notification-Signature` header と body を HMAC-SHA512 で検証。不一致の場合は `401` を返す
- **GitHub App credentials**: Secret Manager 経由で Cloud Run に提供
- **Cloud Run SA**: 最小権限 (Secret Manager accessor のみ)
- **(推奨) Cloud Armor**: TFC の outbound IP を allowlist に設定
- **構造化ログ**: 全リクエストを Cloud Logging に記録 (run_id, workspace_name, dispatch 先, 結果)

</details>

---

## Coexistence with Phase 1

This router is not invoked unless a TFC Notification is configured. Phase 1 (polling) and Phase 2 (webhook) can coexist per-service.

| State | Cloud Run router | Behavior |
|-------|------------------|----------|
| Phase 1 only | Not deployed | Polling (existing) |
| Transitional | Deployed | Opt-in per service |
| Phase 2 only | Deployed | Webhook |

<details><summary>Ja</summary>

本 router は TFC Workspace に Notification が設定されていない限り呼び出されない。Phase 1 (polling) と Phase 2 (webhook) は service 単位で混在可能。

</details>
