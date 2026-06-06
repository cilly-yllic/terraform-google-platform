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

## 非対象範囲

以下はこの bootstrap script では扱いません:

- Project Factory HCL module の実行
- Firebase Project 化 / Firebase Platform HCL
- Terraform Cloud Workspace の作成・管理 (infra-orchestrator 側の責務)
- Billing Account の台帳管理

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
