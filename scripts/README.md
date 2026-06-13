# scripts/

Bootstrap スクリプト群のリファレンス。メインスクリプトは [`bootstrap.sh`](bootstrap.sh)。

## bootstrap.sh

`infra-bootstrap` GCP Project / Service Account / Workload Identity Federation を構築するスクリプト。
Terraform Cloud が `terraform-project-factory` SA を OIDC 経由で impersonate できる状態を作ります。

詳細な背景・前提条件・トラブルシューティングは [docs/project-bootstrap/bootstrap.md](../docs/project-bootstrap/bootstrap.md) を参照してください。

---

## クイックスタート

```bash
# 1. .env テンプレートを生成
scripts/bootstrap.sh --init          # 対話形式で .env / .envrc を選択
scripts/bootstrap.sh --init=env      # 非対話で .env を生成
scripts/bootstrap.sh --init=envrc    # 非対話で .envrc を生成 (direnv 向け)

# 2. 生成されたファイルを編集
vi .env

# 3. 設定の自己診断 (GCP API 呼び出しなし)
scripts/bootstrap.sh --dry-run

# 4. GCP 側の事前確認 (API を呼び出してリソース状態を検証)
make bootstrap-check

# 5. リソース作成
make bootstrap

# 6. Terraform Cloud Workspace に設定する値を確認
make bootstrap-print-env
```

---

## Subcommands

| Subcommand   | 概要 | GCP API 呼び出し |
|-------------- |------|:---------:|
| `check`      | コマンド・認証・環境変数・既存 GCP リソースの状態を検証 | あり |
| `apply`      | bootstrap リソースを作成 (冪等)。内部で `check` を先に実行 | あり |
| `print-env`  | Terraform Cloud Workspace に設定すべき変数値を出力 | あり |

```bash
scripts/bootstrap.sh check
scripts/bootstrap.sh apply
scripts/bootstrap.sh print-env
```

Makefile ターゲット経由でも実行できます:

```bash
make bootstrap-check     # -> scripts/bootstrap.sh check
make bootstrap           # -> scripts/bootstrap.sh apply
make bootstrap-print-env # -> scripts/bootstrap.sh print-env
```

---

## Options

| Option | Short | 説明 |
|--------|-------|------|
| `--help` | `-h` | Usage / subcommand / オプション / 環境変数の一覧を表示 |
| `--dry-run` | `-d` | GCP API を呼び出さず、環境変数の充足状況と設定サマリーを表示 |
| `--init` | `-i` | `.env` または `.envrc` のテンプレートを `bootstrap.example.env` から生成 |
| `--init=env` | — | 非対話で `.env` を生成 |
| `--init=envrc` | — | 非対話で `.envrc` (direnv 用 `export` 形式) を生成 |

### `--help`

```bash
scripts/bootstrap.sh --help
scripts/bootstrap.sh -h
```

### `--dry-run`

環境変数の設定状況を一覧表示します。`check` subcommand との違い:

| | `--dry-run` | `check` |
|---|---|---|
| 目的 | `.env` / シェル環境の self-check | GCP 側リソースの存在確認 |
| GCP API 呼び出し | なし | あり |
| `gcloud` 認証 | 不要 | 必要 |

```bash
scripts/bootstrap.sh --dry-run
scripts/bootstrap.sh -d
```

出力例:

```text
[INFO]  Loaded .env from /path/to/.env

============================================
 Required Variables
============================================
  BOOTSTRAP_PROJECT_ID                          in***ot
  BOOTSTRAP_PROJECT_NAME                        in***ot
  BILLING_ACCOUNT_ID                            XX***XX
  ...

============================================
 Organization / Folder
============================================
  ORGANIZATION_ID                               12***12

============================================
 Optional Variables
============================================
  CONFIRM_BEFORE_APPLY                          true
  ...

[INFO]  All required variables are set. Ready to run 'check' or 'apply'.
```

### `--init`

`scripts/bootstrap.example.env` をベースに `.env` または `.envrc` テンプレートを生成します。

- 既存ファイルが存在する場合は上書きせず、エラーで終了します
- `.envrc` を選択した場合は各変数行の先頭に `export ` が付与されます

```bash
# 対話形式 (1: .env / 2: .envrc を選択)
scripts/bootstrap.sh --init

# 非対話形式
scripts/bootstrap.sh --init=env
scripts/bootstrap.sh --init=envrc
```

---

## 環境変数

テンプレート: [`bootstrap.example.env`](bootstrap.example.env)

### 必須

| 変数名 | 説明 |
|--------|------|
| `BOOTSTRAP_PROJECT_ID` | Bootstrap 用 GCP Project ID |
| `BOOTSTRAP_PROJECT_NAME` | Project の表示名 |
| `BILLING_ACCOUNT_ID` | 紐付ける Billing Account ID |
| `TERRAFORM_PROJECT_FACTORY_SA_ID` | Terraform 用 Service Account ID |
| `WORKLOAD_IDENTITY_POOL_ID` | WIF Pool ID |
| `WORKLOAD_IDENTITY_PROVIDER_ID` | WIF Provider ID |
| `TFC_ORGANIZATION_NAME` | Terraform Cloud Organization 名 |

### 必須 (いずれか一方)

| 変数名 | 説明 |
|--------|------|
| `ORGANIZATION_ID` | GCP 組織の数値 ID |
| `FOLDER_ID` | GCP フォルダの数値 ID |

両方同時に指定するとエラーになります。いずれか一方のみを設定してください。

### オプション

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `TERRAFORM_PROJECT_FACTORY_SA_DISPLAY_NAME` | `Terraform Project Factory` | SA の表示名 |
| `WORKLOAD_IDENTITY_POOL_DISPLAY_NAME` | `Terraform Cloud` | Pool の表示名 |
| `WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME` | `Terraform Cloud` | Provider の表示名 |
| `CONFIRM_BEFORE_APPLY` | `true` | `apply` 実行前に確認プロンプトを表示するか |

### オプション (Budget)

`BUDGET_AMOUNT` を設定した場合のみ Budget が作成されます。

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `BUDGET_AMOUNT` | — | 月次予算額 (例 `1000`)。未設定なら Budget は作成しない |
| `BUDGET_CURRENCY` | `USD` | 通貨 |
| `BUDGET_DISPLAY_NAME` | `${BOOTSTRAP_PROJECT_NAME} Budget` | Budget の表示名 |
| `BUDGET_SCOPE` | `project` | `project` (Bootstrap Project のみ監視) / `billing-account` (Billing Account 全体) |
| `BUDGET_THRESHOLDS` | `0.1,0.3,0.5,0.9,1.0` | アラート閾値 (カンマ区切り、0.0〜1.0) |

### オプション (Cloud Run router deploy 拡張)

`ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"` を設定した場合のみ、cloud-run-router を GitHub Actions から Cloud Run にデプロイするための SA / WIF Provider を追加作成します。
詳細は [Cloud Run router deploy 拡張](#cloud-run-router-deploy-拡張-opt-in) セクション参照。

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `ENABLE_CLOUD_RUN_DEPLOY_SETUP` | `false` | `true` で拡張機能を有効化 (opt-in) |
| `GITHUB_REPOSITORY` | — | `owner/repo`。WIF Provider の attribute condition で deploy を許可する repo (拡張機能有効時は必須) |
| `CLOUD_RUN_DEPLOY_SA_ID` | `cloud-run-router-deploy` | deploy SA ID |
| `CLOUD_RUN_DEPLOY_SA_DISPLAY_NAME` | `Cloud Run Router Deploy` | deploy SA 表示名 |
| `CLOUD_RUN_RUNTIME_SA_ID` | `cloud-run-router-runtime` | runtime SA ID (Cloud Run service の実行 identity) |
| `CLOUD_RUN_RUNTIME_SA_DISPLAY_NAME` | `Cloud Run Router Runtime` | runtime SA 表示名 |
| `GITHUB_WIF_PROVIDER_ID` | `github-actions` | GitHub OIDC Provider ID (既存 Pool 内) |
| `GITHUB_WIF_PROVIDER_DISPLAY_NAME` | `GitHub Actions` | GitHub Provider 表示名 |

---

## Cloud Run router deploy 拡張 (opt-in)

`scripts/bootstrap.sh` は、デフォルトでは Terraform Cloud → GCP 用の WIF / SA だけを構成します。`.env` で以下 2 行を有効化することで、**cloud-run-router を GitHub Actions から Cloud Run にデプロイするための追加リソース**も同時に provision できます。

```bash
ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"
GITHUB_REPOSITORY="owner/repo"
```

### 何が追加で作られるか

| リソース | 内容 |
|---------|------|
| API enable | `run.googleapis.com` / `artifactregistry.googleapis.com` / `cloudbuild.googleapis.com` / `secretmanager.googleapis.com` |
| **runtime SA** (`cloud-run-router-runtime`) | Cloud Run service の実行 identity。`roles/secretmanager.secretAccessor` のみ付与 (TFC_NOTIFICATION_SECRET 等を読む) |
| **deploy SA** (`cloud-run-router-deploy`) | GitHub Actions が impersonate する identity。`roles/run.developer` / `roles/artifactregistry.writer` / `roles/cloudbuild.builds.editor` / `roles/storage.admin` / `roles/iam.serviceAccountTokenCreator` を project 全体に付与、加えて runtime SA に対して `roles/iam.serviceAccountUser` (Cloud Run の `--service-account=<runtime>` 用) |
| **GitHub WIF Provider** | 既存 WIF Pool に追加。issuer = `https://token.actions.githubusercontent.com`、attribute condition = `assertion.repository == "${GITHUB_REPOSITORY}"` で 1 つの repo に厳格に絞る |
| **WIF binding** | GitHub principalSet → deploy SA への `roles/iam.workloadIdentityUser` |

### deploy SA と runtime SA を分ける理由

最小権限の原則に基づき、**deploy 時に必要な権限** (image push / service deploy 等) と **service の runtime に必要な権限** (Secret 読み取り) を別 SA に分離。`--service-account=<runtime SA>` で deploy することで、Cloud Run service は runtime SA の権限だけで動き、deploy SA の強い権限は service の runtime には残らない。

### セットアップフロー

```bash
# 1. .env に opt-in 設定を追加
echo 'ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"' >> .env
echo 'GITHUB_REPOSITORY="owner/repo"' >> .env

# 2. 事前確認 (新リソースが "does not exist" 表示になるはず)
make bootstrap-check

# 3. 再 apply (既存リソースは skip、新リソースだけ作成される)
make bootstrap

# 4. GitHub Actions に設定すべき値を出力
make bootstrap-print-env
```

`make bootstrap-print-env` の出力には、Terraform Cloud 用の値に加えて GitHub Repository Variables 用の値も含まれます:

```text
============================================
 GitHub Actions Repository Variables / Secrets
============================================

GCP_PROJECT_ID=infra-bootstrap
GCP_WORKLOAD_IDENTITY_PROVIDER=projects/{number}/locations/global/workloadIdentityPools/terraform-cloud/providers/github-actions
GCP_DEPLOY_SERVICE_ACCOUNT=cloud-run-router-deploy@infra-bootstrap.iam.gserviceaccount.com
GCP_RUNTIME_SERVICE_ACCOUNT=cloud-run-router-runtime@infra-bootstrap.iam.gserviceaccount.com
```

これらを GitHub repository の **Settings → Secrets and variables → Actions → Variables** に登録すれば、`google-github-actions/auth@v2` で WIF 認証して `gcloud run deploy` する workflow が組めます (workflow 自体は [cloud-run-router/README.md](../cloud-run-router/README.md) 参照)。

### 既存プロジェクトに後から追加する場合

`bootstrap.sh` は **完全冪等** (全リソースで check-then-skip パターン)。既に `make bootstrap` で TFC 用 WIF / SA を作成済みの環境でも、`.env` に上記 2 行を追加して `make bootstrap` を再実行するだけで、既存リソースは触らず Cloud Run deploy 用リソースだけが追加されます。

---

## Cloud Run router runtime secrets

Cloud Run service が runtime で読む 2 つの secret (GCP Secret Manager の `tfc-notification-secret` と `github-app-private-key`) は **deploy workflow が GitHub Secrets から自動 sync** する設計です。GitHub Secrets が **single source of truth**。

### データフロー (推奨)

```
[GitHub Org-level Secrets]
   TFC_NOTIFICATION_SECRET        (= TFC HMAC shared secret)
   GH_APP_PRIVATE_KEY    (= GitHub App PEM)
        │ visibility=selected
        ├─ deploy repo (your-org/<deploy-repo>)
        │     ↓ deploy workflow の sync step
        │ [Secret Manager] tfc-notification-secret / github-app-private-key
        │     ↓ Cloud Run --set-secrets
        │ [Cloud Run service] TFC_NOTIFICATION_SECRET / GITHUB_APP_PRIVATE_KEY env
        │
        └─ project repos (your-org/service1, /service2, ...)
              ↓ Action A が secrets.TFC_NOTIFICATION_SECRET を TFC Notification Token として登録
          [TFC Workspace] Notification (HMAC で webhook 署名)
```

### 必要な事前セットアップ

| 作業 | 場所 | 方法 |
|------|------|------|
| 1. `TFC_NOTIFICATION_SECRET` を GitHub Secrets に登録 | org-level (推奨) | `openssl rand -hex 32` で値生成 → GitHub UI / `gh secret set --org <org> --visibility selected --repos <deploy-repo>,<svc1>,<svc2>` |
| 2. `GH_APP_PRIVATE_KEY` を GitHub Secrets に登録 | org-level (推奨) | GitHub App 設定で生成した `.pem` の内容を GitHub Secret に貼り付け |
| 3. bootstrap.sh で Secret Manager container を作成 (opt-in 経由で自動) | GCP | `make bootstrap` (`ENABLE_CLOUD_RUN_DEPLOY_SETUP=true`) |
| 4. deploy SA に `secretVersionAdder` 付与 (opt-in 経由で自動) | GCP | 上記と同じく `make bootstrap` |

3 と 4 は `make bootstrap` opt-in セットアップに既に含まれています。1 と 2 は手動 (org-level secret 設定は単一ポイントなので 1 回だけ)。

### Deploy 時の自動 sync

deploy workflow ([`examples/cloud-run-router-deploy/deploy-cloud-run-router.yml`](../examples/cloud-run-router-deploy/deploy-cloud-run-router.yml) 参照) は Cloud Run deploy 直前に:

```yaml
- name: Sync runtime secrets to Secret Manager
  env:
    TFC_NOTIFICATION_SECRET: ${{ secrets.TFC_NOTIFICATION_SECRET }}
    GH_APP_PRIVATE_KEY: ${{ secrets.GH_APP_PRIVATE_KEY }}
  run: |
    printf '%s' "${TFC_NOTIFICATION_SECRET}"      | gcloud secrets versions add tfc-notification-secret \
      --project="${{ vars.GCP_PROJECT_ID }}" --data-file=-
    printf '%s' "${GH_APP_PRIVATE_KEY}"  | gcloud secrets versions add github-app-private-key \
      --project="${{ vars.GCP_PROJECT_ID }}" --data-file=-
```

を実行し、各 secret に新 version を追加してから Cloud Run の新 revision を deploy。新 revision は最新 version を読むので、**deploy ごとに最新 GitHub Secret 値が確実に runtime に反映** されます。

### Rotation フロー

| Secret | Rotation 手順 |
|--------|-------------|
| **GH_APP_PRIVATE_KEY (PEM)** | (a) GitHub App 設定で新 private key 生成 → `.pem` ダウンロード → (b) GitHub Secret `GH_APP_PRIVATE_KEY` を新値に更新 → (c) deploy を実行 (revision 更新) → 完了 ✓ |
| **TFC_NOTIFICATION_SECRET (HMAC)** | (a) `openssl rand -hex 32` で新値生成 → (b) GitHub Secret `TFC_NOTIFICATION_SECRET` を新値に更新 → (c) deploy を実行 → Cloud Run runtime は新値で動く ✓ ※ ただし **既存 TFC Notification の Token は古い値のまま** なので、Action A を各 project repo で再実行して Notification を上書きする必要がある (現状の Action A は idempotent create のみで Token update path 未対応 — TFC UI で手動更新 or Action A 拡張が必要) |

### 検証 (`make bootstrap-print-env`)

`ENABLE_CLOUD_RUN_DEPLOY_SETUP=true` のとき、`make bootstrap-print-env` の出力に以下 2 セクションが追加され、**全インフラ設定値の状態を一望できる** 設計です:

```text
============================================
 Runtime Secrets (GCP Secret Manager)
============================================

  tfc-notification-secret        ✓ configured (versions: 1)
  github-app-private-key         ✗ 未設定  → deploy workflow を一度実行すれば版が追加される

============================================
 TFC_NOTIFICATION_SECRET sync targets (.env)
============================================

  Mode: org-level (GH_ORG=your-org, visibility=selected)

  ✓ your-org/service1
  ✓ your-org/service2
```

> Note: `(versions: 0)` 状態でも container 自体は bootstrap 完了で作成済み。最初の deploy で version 1 が追加されます。

---

### Fallback: `make` ターゲット (DEPRECATED)

> ⚠️ 以下の make ターゲット (`setup-router-hmac` / `rotate-router-hmac` / `sync-router-hmac` / `set-github-app-private-key`) は **deprecated** です。実行時に警告が出ます。
>
> 通常運用では使用しないでください。GitHub Secrets が source of truth で、deploy workflow が同期します。

これらは以下のケースの fallback として残してあります:

- ローカル開発 / debug 用に直接 Secret Manager を触りたい
- deploy pipeline が動かない緊急時に PEM / HMAC を Secret Manager に直接投入したい
- 初回 bootstrap 完了直後、まだ deploy を一度も走らせていない時の事前検証

```bash
# 直接 HMAC を生成して Secret Manager + GitHub Secret に push
make setup-router-hmac

# 既存値を rotate
make rotate-router-hmac

# 新規 repo に既存値を同期
make sync-router-hmac

# PEM を Secret Manager に直接投入
make set-github-app-private-key PEM=path/to/key.pem
```

`.env` 設定 (org-level / repo-level の切り替え):

```bash
# (推奨) org-level secret: visibility=selected で対象 repo を限定
GH_ORG="your-org"
TFC_NOTIFICATION_SECRET_REPOS="your-org/service1 your-org/service2"

# (fallback) repo-level secret: GH_ORG を未設定にすると各 repo に個別 set
# TFC_NOTIFICATION_SECRET_REPOS="your-org/service1 your-org/service2"
```

---

## `.env` と `.envrc` の使い分け

| ファイル | ロード方法 | 用途 |
|---------|-----------|------|
| `.env` | `source .env` (bootstrap.sh が自動で読む) | 通常利用 |
| `.envrc` | `direnv allow` (シェル進入時に自動ロード) | [direnv](https://direnv.net/) 利用者向け |

`bootstrap.sh` は `.env` を自動で読み込みます。`.envrc` を使う場合は、`direnv allow` でシェルに変数をロードした状態でスクリプトを実行してください (`.env` が存在しない場合はシェル環境の変数を参照します)。

---

## create-billing-account.sh

GCP Billing Account を master billing account 配下に新規作成するスクリプト。
作成した Billing Account ID は `bootstrap.sh` の `.env` (`BILLING_ACCOUNT_ID`) に設定して使用します。

詳細な背景・前提条件・トラブルシューティングは [docs/project-bootstrap/create-billing-account.md](../docs/project-bootstrap/create-billing-account.md) を参照してください。

> **注意**: master billing account (Reseller / Channel Partner) を持つ場合のみ利用可能です。

### クイックスタート

```bash
# 1. .env.billing テンプレートを生成
scripts/create-billing-account.sh --init          # 対話形式
scripts/create-billing-account.sh --init=env      # 非対話で .env.billing を生成
scripts/create-billing-account.sh --init=envrc    # 非対話で .envrc.billing を生成

# 2. 生成されたファイルを編集
vi .env.billing

# 3. 設定の自己診断 (GCP API 呼び出しなし)
scripts/create-billing-account.sh --dry-run

# 4. GCP 側の事前確認
make create-billing-account-check

# 5. Billing Account 作成
make create-billing-account

# 6. 作成された Billing Account ID を確認
make create-billing-account-print-env
```

### Subcommands

| Subcommand   | 概要 | GCP API 呼び出し |
|-------------- |------|:---------:|
| `check`      | コマンド・認証・環境変数・master billing account の状態を検証 | あり |
| `apply`      | Billing Account を作成 (冪等)。内部で `check` を先に実行 | あり |
| `print-env`  | 作成された Billing Account ID と bootstrap 連携値を出力 | あり |

```bash
make create-billing-account-check     # -> scripts/create-billing-account.sh check
make create-billing-account           # -> scripts/create-billing-account.sh apply
make create-billing-account-print-env # -> scripts/create-billing-account.sh print-env
```

### 環境変数

テンプレート: [`create-billing-account.example.env`](create-billing-account.example.env)

| 変数名 | 必須 | 説明 |
|--------|:---:|------|
| `BILLING_DISPLAY_NAME` | ✓ | 新規 Billing Account の表示名 |
| `MASTER_BILLING_ACCOUNT_ID` | ✓ | 親となる Master Billing Account ID |
| `ORGANIZATION_ID` | — | 紐付ける GCP Organization の数値 ID |
| `CONFIRM_BEFORE_APPLY` | — | `apply` 前の確認プロンプト (default: `true`) |

---

## 関連ドキュメント

- [docs/project-bootstrap/bootstrap.md](../docs/project-bootstrap/bootstrap.md) — 前提条件・実行手順の詳細・トラブルシューティング
- [docs/project-bootstrap/create-billing-account.md](../docs/project-bootstrap/create-billing-account.md) — Billing Account 作成ガイド
- [docs/project-bootstrap/design/iam-policy.md](../docs/project-bootstrap/design/iam-policy.md) — IAM role 付与の設計根拠
- [docs/project-bootstrap/design/wif-attribute-mapping.md](../docs/project-bootstrap/design/wif-attribute-mapping.md) — WIF Attribute Mapping の詳細
