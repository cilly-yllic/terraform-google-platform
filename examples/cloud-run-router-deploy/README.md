# Cloud Run router deploy (reference workflow)

`cloud-run-router/` を Cloud Run にデプロイするための GitHub Actions workflow の **reference 実装** です。本リポジトリ内では実行されません (`examples/` 配下にあるため GitHub Actions に自動拾い上げされない)。

利用者は本 workflow を **自リポジトリの private な deploy 用 repo にコピー** して使うことを想定しています。

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
                  ├─ deploy-cloud-run-router.yml  ← これをコピー
                  └─ README.md                    ← (本ファイル)

[Private] <your-org>/<your-deploy-repo>            (新規 / 既存 private repo)
          └─ .github/workflows/
              └─ deploy-cloud-run-router.yml      ← コピー先 + 微修正
                  ↓
                  actions/checkout で public repo の指定 tag を取得
                  → gcloud builds submit (image build & push)
                  → gcloud run deploy (Cloud Run service 更新)
                  → Slack 通知
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
curl -O https://raw.githubusercontent.com/cilly-yllic/terraform-google-platform/main/examples/cloud-run-router-deploy/deploy-cloud-run-router.yml
mv deploy-cloud-run-router.yml .github/workflows/
```

もしくはコピペでも OK。配置後、ファイル先頭の `SOURCE_REPO:` を自分の使う source repo に合わせて変更してください (本リポジトリを fork してる場合は fork 先を指定)。

### 3. private deploy repo の Variables を登録

**Settings → Secrets and variables → Actions → Variables** に以下を登録 (`make bootstrap-print-env` の出力をコピペ):

| Variable | 例 | 取得元 |
|----------|---|--------|
| `GCP_PROJECT_ID` | `infra-bootstrap` | bootstrap-print-env |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/<num>/locations/global/workloadIdentityPools/terraform-cloud/providers/github-actions` | bootstrap-print-env |
| `GCP_DEPLOY_SERVICE_ACCOUNT` | `cloud-run-router-deploy@<project>.iam.gserviceaccount.com` | bootstrap-print-env |
| `GCP_RUNTIME_SERVICE_ACCOUNT` | `cloud-run-router-runtime@<project>.iam.gserviceaccount.com` | bootstrap-print-env |
| `GH_APP_ID` | `123456` (数値) | GitHub App 設定画面の App ID |

> **注意**: `GITHUB_APP_ID` という名前は GitHub Actions の予約 prefix `GITHUB_` に当たるため Variable / Secret として作成できません。`GH_APP_ID` で登録し、workflow 内で `--set-env-vars="GITHUB_APP_ID=${{ vars.GH_APP_ID }}"` の形で env 名をリマップします。

### 4. private deploy repo の Secrets を登録

**Settings → Secrets and variables → Actions → Secrets** に:

| Secret | 用途 |
|--------|------|
| `DEPLOY_WEBHOOK` | Slack Incoming Webhook URL (deploy 成功通知) |

### 5. GCP Secret Manager に runtime secret を作成

cloud-run-router の runtime 用 secret を Secret Manager に作成:

```bash
# TFC notification HMAC secret
gcloud secrets create tfc-notification-secret \
  --data-file=<(printf '%s' "<your-tfc-hmac-secret>") \
  --project=<GCP_PROJECT_ID>

# GitHub App private key (PEM)
gcloud secrets create github-app-private-key \
  --data-file=path/to/github-app-private-key.pem \
  --project=<GCP_PROJECT_ID>
```

`tfc-notification-secret` の値は TFC 側 Notification 設定の Token と必ず一致させてください。

---

## 運用フロー

```
1. source repo (cilly-yllic/terraform-google-platform 等) の main で
   `cloud-run-router-v<semver>` 形式のタグを切る
       例: git tag cloud-run-router-v1.0.0 && git push origin cloud-run-router-v1.0.0

2. private deploy repo の Actions → "Deploy cloud-run-router" → Run workflow
       Tag input に `cloud-run-router-v1.0.0` を入力 → Run

3. workflow が:
   - tag を fetch → main 祖先チェック
   - WIF 認証
   - gcloud builds submit でコンテナイメージを build & push
   - gcloud run deploy で Cloud Run を更新 (runtime SA で実行)
   - Slack に Service URL + /webhook endpoint URL を含めて通知
```

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

### `Tag <X> is not reachable from <repo> main`

別ブランチに切られたタグからの deploy は workflow で reject されます。main に merge された commit に対してタグを切り直してください。

### Slack 通知が来ない

deploy 自体は成功しているなら通知 step の失敗。`continue-on-error: true` を設定してるので workflow 全体は success のまま続行します。Slack webhook URL が無効化されていないか確認。
