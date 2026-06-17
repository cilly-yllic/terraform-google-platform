# Bootstrap Guide

## 概要

この bootstrap script は、Terraform Cloud / HCP Terraform が `terraform-project-factory` Service Account を Workload Identity Federation (WIF) / OIDC 経由で impersonate できる状態を作るためのものです。

具体的には以下のリソースを作成します:

- `infra-bootstrap` GCP Project
- `terraform-project-factory` Service Account
- Workload Identity Pool / Provider (Terraform Cloud 用 OIDC)
- Terraform Cloud Organization から `terraform-project-factory` を impersonate するための IAM binding

Service Account Key JSON は一切作成しません。

## 前提条件

- `gcloud` CLI がインストール済みであること
- `gcloud auth login` で認証済みであること
- 以下の権限を持つアカウントで実行すること:
  - Organization または Folder に対する `resourcemanager.projects.create`
  - Billing Account に対する `billing.resourceAssociations.create`
  - IAM 関連の管理権限

## 実行手順

### 1. 環境変数ファイルの準備

```bash
cp scripts/bootstrap.example.env .env
vi .env
```

`.env` に組織固有の値を設定してください。

### 2. 事前確認

```bash
make bootstrap-check
```

必要なコマンド、認証状態、環境変数、既存リソースの状態を確認します。作成処理は行いません。

### 3. リソース作成

```bash
make bootstrap
```

以下を順に実行します:

1. 入力値検証
2. `infra-bootstrap` Project 作成
3. Billing Account 紐付け
4. 必要 API 有効化
5. `terraform-project-factory` Service Account 作成
6. IAM role 付与
7. Workload Identity Pool 作成
8. Workload Identity Provider 作成
9. Terraform Cloud Organization → `terraform-project-factory` の WIF binding 作成
10. Terraform Cloud Workspace に設定すべき値の出力

`CONFIRM_BEFORE_APPLY="true"` の場合、実行前に確認プロンプトが表示されます。

### 4. Terraform Cloud 設定値の確認

```bash
make bootstrap-print-env
```

出力例:

```text
TFC_GCP_PROVIDER_AUTH=true
TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL=terraform-project-factory@infra-bootstrap.iam.gserviceaccount.com
TFC_GCP_WORKLOAD_PROVIDER_NAME=projects/{project_number}/locations/global/workloadIdentityPools/terraform-cloud/providers/terraform-cloud
GOOGLE_PROJECT=infra-bootstrap
```

## Terraform Cloud への設定

`make bootstrap-print-env` の出力を、後続の Project Factory Workspace の Environment Variables に設定してください。

- `TFC_GCP_PROVIDER_AUTH` → `true`
- `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` → Service Account email
- `TFC_GCP_WORKLOAD_PROVIDER_NAME` → Workload Identity Provider の full name
- `GOOGLE_PROJECT` → bootstrap Project ID

## オプション拡張: cloud-run-router deploy リソース

`.env` で `ENABLE_CLOUD_RUN_DEPLOY_SETUP="true"` + `GITHUB_REPOSITORY="owner/repo"` を設定して再実行すると、cloud-run-router を GitHub Actions から Cloud Run にデプロイするためのリソースも同時に provision されます。

### 追加で作られるリソース

1. 追加 API enable
   - `run.googleapis.com` / `artifactregistry.googleapis.com` / `cloudbuild.googleapis.com` / `secretmanager.googleapis.com`
2. **Cloud Run runtime SA** (`cloud-run-router-runtime`)
   - Cloud Run service の実行 identity (最小権限)
   - 付与 role: `roles/secretmanager.secretAccessor` のみ
3. **Cloud Run deploy SA** (`cloud-run-router-deploy`)
   - GitHub Actions が impersonate する identity
   - Project レベル: `roles/run.admin` (deploy + `--allow-unauthenticated` 用の `setIamPolicy`) / `roles/artifactregistry.writer` / `roles/cloudbuild.builds.editor` / `roles/storage.admin` / `roles/secretmanager.secretVersionAdder`
   - runtime SA リソース限定: `roles/iam.serviceAccountUser` (Cloud Run `--service-account=<runtime>` のため) + `roles/iam.serviceAccountTokenCreator` (runtime SA の token 発行。project レベルにせず対象 SA に絞り、他 SA への成り代わりを防ぐ)
4. **GitHub WIF Provider** (既存 Pool 内に追加)
   - issuer: `https://token.actions.githubusercontent.com`
   - attribute condition: `assertion.repository_owner == "${GITHUB_OWNER}"` — **org 単位**のゲート (`GITHUB_OWNER` 未指定時は `GITHUB_REPOSITORY` の owner)。repo 単位の制限は各 SA の WIF binding (`attribute.repository/{owner}/{repo}`) で行う。これによりサービス repo の GitHub Actions が各 firebase project の `ci_service_account` を impersonate して deploy できる
5. **WIF binding**: GitHub principalSet → deploy SA への `roles/iam.workloadIdentityUser`

### deploy SA と runtime SA を分ける理由

最小権限の原則に基づき、deploy 時の権限と service runtime の権限を分離。`gcloud run deploy --service-account=<runtime>` で deploy することで、Cloud Run service は runtime SA の権限だけで動き、強い deploy SA は service 内には残らない。

### 既存プロジェクトへの後付け

`bootstrap.sh` は全リソースで check-then-skip パターンで構成されており**完全冪等**。既に TFC 用 WIF / SA を構築済みの環境でも、`.env` に上記 2 行を追記して `make bootstrap` を再実行するだけで、既存リソースは触らず Cloud Run deploy 用リソースだけが追加されます。

### 設定値の取り出し

`make bootstrap-print-env` の出力に、Terraform Cloud 用に加えて GitHub Actions Repository Variables 用のセクションが追加されます。`GCP_WORKLOAD_IDENTITY_PROVIDER` / `GCP_DEPLOY_SERVICE_ACCOUNT` / `GCP_RUNTIME_SERVICE_ACCOUNT` 等を GitHub repo の Variables に登録して、`google-github-actions/auth@v2` で WIF 認証する workflow を構成します。

詳しくは [scripts/README.md#cloud-run-router-deploy-拡張-opt-in](../../scripts/README.md#cloud-run-router-deploy-拡張-opt-in) を参照。

## 非対象範囲

以下はこの bootstrap script では扱いません:

- Project Factory HCL module の実行
- Firebase Project 化 / Firebase Platform HCL
- Terraform Cloud Workspace の作成・管理 (infra-orchestrator 側の責務)
- Billing Account の台帳管理
- cloud-run-router の container image build / Cloud Run service の deploy 自体 (上記の拡張で provision するのは認証 / 権限基盤のみ)

## トラブルシューティング

### Billing Account 権限不足

```text
ERROR: (gcloud.billing.projects.link) User does not have permission ...
```

`gcloud auth login` で使用しているアカウントに Billing Account の `billing.resourceAssociations.create` 権限があるか確認してください。

### Project 作成権限不足

```text
ERROR: (gcloud.projects.create) ... does not have resourcemanager.projects.create permission
```

Organization または Folder に対する `resourcemanager.projects.create` 権限が必要です。Organization Admin または適切な IAM role を確認してください。

### API 有効化失敗

```text
ERROR: (gcloud.services.enable) PERMISSION_DENIED
```

Project に Billing Account が紐付いていない可能性があります。`make bootstrap-check` で Billing Account の状態を確認してください。

### Service Account 作成失敗

```text
ERROR: (gcloud.iam.service-accounts.create) ... PERMISSION_DENIED
```

`iam.googleapis.com` API が有効化されているか確認してください。`make bootstrap` は API 有効化を先に行いますが、既存 Project に対して手動で実行する場合は API が有効でないことがあります。

### Workload Identity Pool 作成失敗

```text
ERROR: (gcloud.iam.workload-identity-pools.create) ... PERMISSION_DENIED
```

`iam.googleapis.com` および `iamcredentials.googleapis.com` API が有効化されているか確認してください。

### Workload Identity Provider 作成失敗

```text
ERROR: (gcloud.iam.workload-identity-pools.providers.create-oidc) ... ALREADY_EXISTS
```

同名の Provider が既に存在します。`make bootstrap-check` で状態を確認してください。削除済みの Pool/Provider が soft-delete 状態で残っている場合は、`gcloud iam workload-identity-pools undelete` で復元するか、別の ID を使用してください。

### Terraform Cloud から impersonation できない

Terraform Cloud の Run で以下のエラーが出る場合:

```text
Error: could not obtain access token ... PermissionDenied
```

以下を確認してください:

1. `TFC_GCP_WORKLOAD_PROVIDER_NAME` が正しいか (`make bootstrap-print-env` の出力と一致するか)
2. `TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL` が正しいか
3. Terraform Cloud Organization 名が `.env` の `TFC_ORGANIZATION_NAME` と一致するか

### Attribute Condition 不一致

Terraform Cloud の Run で認証エラーが出る場合、Workload Identity Provider の Attribute Condition を確認してください:

```bash
gcloud iam workload-identity-pools providers describe terraform-cloud \
  --project=infra-bootstrap \
  --location=global \
  --workload-identity-pool=terraform-cloud \
  --format='value(attributeCondition)'
```

出力に含まれる Organization 名が、実際の Terraform Cloud Organization 名と一致しているか確認してください。

### GitHub Actions から認証できない (Cloud Run deploy 拡張使用時)

GitHub Actions の `google-github-actions/auth@v2` で `Failed to generate Google Cloud federated token` が出る場合:

1. **`GCP_WORKLOAD_IDENTITY_PROVIDER` が正しいか** — `make bootstrap-print-env` の出力 (`projects/{number}/locations/global/workloadIdentityPools/.../providers/github-actions`) と一致するか
2. **attribute condition の repo 名が一致しているか** — `.env` の `GITHUB_REPOSITORY` と、workflow を走らせている GitHub repo が完全一致 (`owner/repo` 形式) であること

```bash
gcloud iam workload-identity-pools providers describe github-actions \
  --project=infra-bootstrap \
  --location=global \
  --workload-identity-pool=terraform-cloud \
  --format='value(attributeCondition)'
```

3. **deploy SA への binding があるか**

```bash
gcloud iam service-accounts get-iam-policy \
  cloud-run-router-deploy@infra-bootstrap.iam.gserviceaccount.com \
  --format=json | jq '.bindings[] | select(.role == "roles/iam.workloadIdentityUser")'
```

`principalSet://...attribute.repository/<owner>/<repo>` が含まれていることを確認。
