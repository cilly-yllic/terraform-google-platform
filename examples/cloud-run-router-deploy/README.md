# Cloud Run router deploy (reference workflows)

`cloud-run-router/` を Cloud Run にデプロイするための GitHub Actions workflow の **reference 実装** 一式です。本リポジトリ内では実行されません (`examples/` 配下にあるため GitHub Actions に自動拾い上げされない)。

利用者は本 workflow を **自リポジトリの private な deploy 用 repo にコピー** して使うことを想定しています。

含まれる workflow:

| ファイル | 用途 |
|---------|------|
| [`deploy-cloud-run-router.yml`](./deploy-cloud-run-router.yml) | source repo の main HEAD を取り、Cloud Run に deploy。Build → Sync runtime secrets (GitHub Secrets → Secret Manager) → Deploy → Cloud Run URL を `CLOUD_RUN_WEBHOOK_URL` Repository Secret に登録 → Slack 通知 |
| [`init-router-hmac.yml`](./init-router-hmac.yml) | TFC HMAC shared secret (`TFC_NOTIFICATION_SECRET`) を CI 内で生成・GitHub Repository Secret に登録 (workflow_dispatch、rotate オプション付き)。**成功で完了すると deploy workflow が自動 trigger される** |

---

## なぜ別 repo に置くのか

cloud-run-router のソースコードは本リポジトリ (公開) で reference implementation として公開されています。一方、その deploy 用 workflow を同じ公開リポジトリに置くと:

- Action ログがパブリックになり、Cloud Run URL / project ID / SA email 等の運用情報が漏れる
- 公開リポジトリの collaborator 全員が deploy 権限を持つことになる
- 悪意ある PR が main に merge された場合、次の deploy で本番に乗る

これらを避けるため、**deploy 系は別の private repo に隔離する**のが推奨パターンです。

```
[Public]  <fork-source>/terraform-google-platform
          ├─ cloud-run-router/        (ソースコード)
          ├─ scripts/bootstrap.sh
          └─ examples/
              └─ cloud-run-router-deploy/
                  ├─ deploy-cloud-run-router.yml   ← コピー
                  ├─ init-router-hmac.yml          ← コピー
                  └─ README.md                     ← (本ファイル)

[Private] <your-org>/<your-deploy-repo>            (新規 / 既存 private repo)
          └─ .github/workflows/
              ├─ deploy-cloud-run-router.yml        ← コピー先 + 微修正
              │   actions/checkout で public repo の指定 tag を取得
              │   → gcloud builds submit (image build & push)
              │   → Sync GitHub Secrets → GCP Secret Manager
              │   → gcloud run deploy (Cloud Run service 更新)
              │   → Slack 通知
              │
              └─ init-router-hmac.yml               ← コピー先 (修正不要)
                  workflow_dispatch で:
                  openssl で HMAC 生成 → GitHub Repository Secret
                  TFC_NOTIFICATION_SECRET に登録
                  (rotate オプション付き)
```

---

## セットアップ手順

### 1. WIF / SA を GCP 側に provision

source repo を clone した状態で `.env` を設定し `make bootstrap` を opt-in モードで実行:

```bash
# .env に追記
cat >> .env <<'ENV'
ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"
GITHUB_REPOSITORY="<your-org>/<your-deploy-repo>"   # ← private deploy repo を指定
ENV

make bootstrap                 # 既存リソース skip + 新リソース作成
make bootstrap-print-env       # GitHub Variables 用の値を出力
```

詳細: [`../../scripts/README.md#cloud-run-router-deploy-拡張-opt-in`](../../scripts/README.md#cloud-run-router-deploy-拡張-opt-in)

### 2. private deploy repo に workflow ファイルを配置

```bash
mkdir -p .github/workflows
# deploy 用 (tag 指定で Cloud Run に deploy)
curl -O https://raw.githubusercontent.com/cilly-yllic/terraform-google-platform/main/examples/cloud-run-router-deploy/deploy-cloud-run-router.yml
mv deploy-cloud-run-router.yml .github/workflows/
# HMAC 自動生成・登録用 (workflow_dispatch)
curl -O https://raw.githubusercontent.com/cilly-yllic/terraform-google-platform/main/examples/cloud-run-router-deploy/init-router-hmac.yml
mv init-router-hmac.yml .github/workflows/
```

もしくはコピペでも OK。配置後、`deploy-cloud-run-router.yml` 先頭の `SOURCE_REPO:` を自分の使う source repo に合わせて変更してください (本リポジトリを fork してる場合は fork 先を指定)。`init-router-hmac.yml` は通常修正不要。

### 3. private deploy repo の Variables を登録

**Settings → Secrets and variables → Actions → Variables** に以下を登録:

| Variable | 例 | 取得元 |
|----------|---|--------|
| `GH_APP_ID` | `123456` (数値) | GitHub App 設定画面の App ID |

> **注意**: `GITHUB_APP_ID` という名前は GitHub Actions の予約 prefix `GITHUB_` に当たるため Variable / Secret として作成できません。`GH_APP_ID` で登録し、workflow 内で `--set-env-vars="GITHUB_APP_ID=${{ vars.GH_APP_ID }}"` の形で env 名をリマップします。

### 4. private deploy repo の Secrets を登録 (手動)

**Settings → Secrets and variables → Actions → Secrets** に以下を登録 (`make bootstrap-print-env` の出力をコピペ):

| Secret | 例 / 用途 | 値の入手元 |
|--------|----------|----------|
| `GCP_PROJECT_ID` | `infra-bootstrap` | bootstrap-print-env |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<num>/locations/global/workloadIdentityPools/terraform-cloud/providers/github-actions` | bootstrap-print-env |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `cloud-run-router-deploy@<project>.iam.gserviceaccount.com` | bootstrap-print-env |
| `GCP_RUNTIME_SERVICE_ACCOUNT` | `cloud-run-router-runtime@<project>.iam.gserviceaccount.com` | bootstrap-print-env |
| `DEPLOY_WEBHOOK` | Slack Incoming Webhook URL (deploy 成功通知) | Slack App 設定 |
| `GH_APP_PRIVATE_KEY` | GitHub App Private Key (PEM 文字列) | GitHub App 設定画面で **Generate a private key** → `.pem` ダウンロード → ファイル全文を貼り付け |

> GCP 関連 (`GCP_*`) は値自体は識別子で公開しても直接被害は出にくいですが、運用上の defense-in-depth として Secret に置く方針です。技術的には Variable でも動かせますが、その場合は workflow 内の `secrets.GCP_*` を `vars.GCP_*` に書き換える必要があります。
>
> `TFC_NOTIFICATION_SECRET` は **手動登録不要**。次の Step 6 の init workflow で **自動生成・登録** されます。

### 5. cloud-run-router GitHub App に Repository Secrets: Write 権限を追加

`init-router-hmac.yml` workflow が GitHub Repository Secret に書き込むため、対象の GitHub App に権限追加が必要です。

1. GitHub App 設定画面 (個人 `https://github.com/settings/apps/<app-name>` または Org `https://github.com/organizations/<org>/settings/apps/<app-name>`) → **Edit**
2. 左メニュー **Permissions & events** → **Repository permissions** セクション
3. **Secrets** を **Read and write** に変更
4. **Save changes**
5. 画面上部に出る黄色いバナーから **Accept new permissions** をクリック (or `https://github.com/settings/installations` → App → Configure)

確認: App の Permissions に以下があれば OK:
- `Contents: Read and write` (既存)
- `Secrets: Read and write` (今回追加)

### 6. `init-router-hmac.yml` を実行して TFC_NOTIFICATION_SECRET を生成

private deploy repo の **Actions** タブ → **Initialize / Rotate TFC_NOTIFICATION_SECRET** → **Run workflow**:
- `rotate`: **false** (default。初回登録)
- **Run workflow** クリック

完了すると `TFC_NOTIFICATION_SECRET` が Repository Secrets に登録されます (値は表示されません)。

> **Rotation 時**: 同じ workflow を `rotate: true` で再実行。新値で上書きされます。ただし既存の TFC Notification の Token は古いまま残るので、各 service の `provision-project` workflow を再実行して TFC Notification を再作成する必要あり (現状の Action A は Token update 未対応のため、TFC UI からの手動更新も併用)。

### 7. GCP Secret Manager の container は bootstrap.sh で既に作成済み

`tfc-notification-secret` と `github-app-private-key` の **空 container** は `make bootstrap` (Step 1) で自動作成されています。**値の投入は次の deploy workflow** が GitHub Secrets から sync するので、手動 `gcloud secrets create` 等は不要。

---

## 運用フロー

### 起動経路

deploy workflow は **2 つのトリガー**で起動:

| 経路 | 操作 | いつ使うか |
|------|------|----------|
| **workflow_dispatch** | Actions → "Deploy cloud-run-router" → **Run workflow** | source repo の main に新しい commit が乗ったときに手動で反映したい |
| **workflow_run** (自動) | "Initialize / Rotate TFC_NOTIFICATION_SECRET" workflow が成功で完了 | HMAC を init / rotate した直後の連鎖 deploy。手動操作不要 |

tag 入力は **廃止**しました。常に source repo の main HEAD を取得して deploy します。image tag は `main-<short-sha>` 形式で commit traceability を確保。

### 1 回の deploy で何が起きるか

```
[Deploy workflow start]
   ↓
1. source repo の main HEAD を checkout
2. WIF 認証
3. gcloud builds submit でコンテナイメージを build & push
   (image tag: main-<source-repo-short-sha>)
4. Sync runtime secrets:
   - secrets.TFC_NOTIFICATION_SECRET → GCP Secret Manager `tfc-notification-secret` 新 version
   - secrets.GH_APP_PRIVATE_KEY      → GCP Secret Manager `github-app-private-key` 新 version
5. gcloud run deploy で Cloud Run の新 revision を作成 (:latest を読む = 上記の最新 version が runtime に乗る)
6. Cloud Run service URL を describe で取得
7. URL + /webhook を Repository Secret `CLOUD_RUN_WEBHOOK_URL` に上書き登録
   (GitHub App token 使用、App に Repository secrets: Write 必要)
8. Slack に Service URL / TFC Notification destination URL を含めて通知
```

### 初回 deploy までの最短手順

セットアップ Step 1〜6 が完了している前提:

```
Actions タブ → "Initialize / Rotate TFC_NOTIFICATION_SECRET" → Run workflow (rotate=false)
   ↓
TFC_NOTIFICATION_SECRET が登録される
   ↓
自動で Deploy workflow が起動 (workflow_run trigger)
   ↓
Cloud Run に初回 revision が deploy + CLOUD_RUN_WEBHOOK_URL が登録される
   ↓
完了 ✨
```

### Rotation 操作

| Secret | Rotation 手順 |
|--------|-------------|
| **TFC_NOTIFICATION_SECRET** (HMAC) | (a) Actions → "Initialize / Rotate TFC_NOTIFICATION_SECRET" → `rotate: true` → Run → (b) **deploy は自動起動** (workflow_run) → 新値が Cloud Run runtime に反映 → (c) 各 service の provision-project workflow を再実行 (or TFC UI で Notification Token を手動更新) |
| **GH_APP_PRIVATE_KEY** (PEM) | (a) GitHub App 設定画面で新 private key 生成 → `.pem` ダウンロード → (b) Repository Secret `GH_APP_PRIVATE_KEY` を新値に更新 → (c) Deploy workflow を手動起動 → 新値が Cloud Run runtime に反映 → (d) GitHub App 設定で古い private key を Revoke |
| **CLOUD_RUN_WEBHOOK_URL** | **rotation 不要**。deploy 毎に最新値で自動上書きされる |

---

## カスタマイズ ポイント

workflow YAML 内の `env:` ブロックを変更すれば調整可:

| 環境変数 | デフォルト | 用途 |
|---------|----------|------|
| `SOURCE_REPO` | `cilly-yllic/terraform-google-platform` | 取得元 public repo |
| `SERVICE_NAME` | `cloud-run-router` | Cloud Run service 名 |
| `REGION` | `asia-northeast1` | Cloud Run / Artifact Registry の region |
| `IMAGE_REPO` | `gcr.io` | image registry (Artifact Registry でも可) |

その他 `gcloud run deploy` の引数 (memory / cpu / max-instances 等) は workflow YAML 内で直接調整してください。

---

## トラブルシューティング

### `Failed to generate Google Cloud federated token`

WIF 認証失敗。確認すべきこと:
1. `GCP_WORKLOAD_IDENTITY_PROVIDER` が `make bootstrap-print-env` の出力と一致しているか
2. **WIF Provider の attribute condition** が **deploy repo の名前**で設定されているか (公開 source repo ではない):

```bash
gcloud iam workload-identity-pools providers describe github-actions \
  --project=<GCP_PROJECT_ID> \
  --location=global \
  --workload-identity-pool=terraform-cloud \
  --format='value(attributeCondition)'
```

→ `assertion.repository == "<your-org>/<your-deploy-repo>"` であることを確認

### `secrets.TFC_NOTIFICATION_SECRET is not set`

`TFC_NOTIFICATION_SECRET` が GitHub Secrets に未登録の状態で deploy が起動された場合。Actions → "Initialize / Rotate TFC_NOTIFICATION_SECRET" を `rotate=false` で実行してください。完了後に deploy が自動で起動します。

### `secrets.GH_APP_PRIVATE_KEY is not set`

`GH_APP_PRIVATE_KEY` (PEM) は手動登録必須です。GitHub App 設定画面で private key を生成 → `.pem` ダウンロード → 内容を Repository Secret に登録してください。

### init workflow 成功後に deploy が走らない

`workflow_run` trigger は workflow ファイルが **default branch (通常 main)** にある状態でのみ発火します。本 workflow が main にマージされる前 (= PR 上で test 実行) では自動 trigger は動きません。マージ後の本番運用で動作します。

### Slack 通知が来ない

deploy 自体は成功しているなら通知 step の失敗。`continue-on-error: true` を設定してるので workflow 全体は success のまま続行します。Slack webhook URL が無効化されていないか確認。
