# Step 1: Bootstrap (infra-bootstrap Project 作成)

`scripts/bootstrap.sh` を使用して、Terraform Cloud が GCP リソースを管理するための基盤を構築します。

---

## 概要

以下のリソースを作成します:

1. `infra-bootstrap` GCP Project
2. `terraform-project-factory` Service Account (org/folder の project 作成・IAM 権限を持つ強権 SA)
3. Workload Identity Pool / Provider (Terraform Cloud 用 OIDC)
4. factory workspace → Factory SA の impersonation IAM binding

Service Account Key JSON は作成しません（WIF / OIDC を使用）。

> **セキュリティ注記**: Factory SA を impersonate できるのは workspace 名が
> `project-factory-` で始まる **factory workspace のみ**です (WIF 派生属性
> `terraform_workspace_kind`)。env ごとの terraform SA は infra ではなく後段の
> `project-bootstrap` module が**各ターゲット project の中**に作ります。
> 全体像は [Getting Started: Service Account / セキュリティモデル](./README.md#service-account--セキュリティモデル-重要) を参照。

---

## 前提条件

- `gcloud` CLI がインストール済み + `gcloud auth login` で認証済み
- 以下の GCP 権限:
  - Organization / Folder に対する `resourcemanager.projects.create`
  - Billing Account に対する `billing.resourceAssociations.create`
  - IAM 関連の管理権限
- Billing Account ID（[Step 0](./00-billing-account.md) で作成、または既存のもの）

---

## 手順

### 1. 環境変数ファイルの準備

```bash
# テンプレートからコピー
cp scripts/bootstrap.example.env .env
vi .env
```

または `--init` オプションで生成:

```bash
scripts/bootstrap.sh --init          # 対話形式 (.env / .envrc を選択)
scripts/bootstrap.sh --init=env      # 非対話 (.env)
scripts/bootstrap.sh --init=envrc    # 非対話 (.envrc / direnv 向け)
```

主要な環境変数:

| 変数名 | 必須 | 説明 |
|--------|:---:|------|
| `BOOTSTRAP_PROJECT_ID` | Yes | Bootstrap 用 GCP Project ID |
| `BOOTSTRAP_PROJECT_NAME` | Yes | Project の表示名 |
| `BOOTSTRAP_BILLING_ACCOUNT_ID` | Yes | 紐付ける Billing Account ID |
| `TERRAFORM_PROJECT_FACTORY_SA_ID` | Yes | Terraform 用 Service Account ID |
| `WORKLOAD_IDENTITY_POOL_ID` | Yes | WIF Pool ID |
| `WORKLOAD_IDENTITY_PROVIDER_ID` | Yes | WIF Provider ID |
| `TFC_ORGANIZATION_NAME` | Yes | Terraform Cloud Organization 名 |
| `ORGANIZATION_ID` | 配置※ | GCP 組織の数値 ID。folder の親 / org 直下運用の配置先 |
| `BOOTSTRAP_FOLDER_NAME` | 配置※ | folder の display name（例 `infra`）。`ORGANIZATION_ID` 配下で検索し、無ければ作成、得られた `BOOTSTRAP_FOLDER_ID` を `.env` に書き戻す。**推奨** |
| `BOOTSTRAP_FOLDER_ID` | 配置※ | 既存 folder を数値 ID で直接指定する場合。`BOOTSTRAP_FOLDER_NAME` 利用時は自動で書き込まれる |

※ 配置モードは次の 3 通り（詳細は [`bootstrap.example.env`](../../scripts/bootstrap.example.env)）:

1. **`BOOTSTRAP_FOLDER_NAME` + `ORGANIZATION_ID`（推奨・一番楽）** — folder を find-or-create して `BOOTSTRAP_FOLDER_ID` を自動解決。folder ID は GCP 自動採番なので display name で扱う。要 caller 権限 `roles/resourcemanager.folderCreator`（org）。
2. **`BOOTSTRAP_FOLDER_ID`（+ `ORGANIZATION_ID`）** — 既存 folder を直接指定。
3. **`ORGANIZATION_ID` のみ** — folder を使わず org 直下。

> **folder 推奨理由**: folder mode では Factory SA の `projectCreator` / `projectIamAdmin` がその folder 内に限定され、影響範囲（blast radius）を封じ込められます。org 直下でも動作しますが Factory SA の到達範囲が org 全体になります（その場合も「factory workspace のみ impersonate 可」の floor は効きます）。
>
> `FACTORY_WORKSPACE_PREFIX`（任意, default `project-factory-`）で factory workspace の命名規約を上書きできます。

全変数の一覧: [`scripts/bootstrap.example.env`](../../scripts/bootstrap.example.env)

### 2. 設定の自己診断（dry-run）

```bash
scripts/bootstrap.sh --dry-run
```

GCP API を呼び出さずに環境変数の充足状況を確認します。

### 3. 事前確認

```bash
make bootstrap-check
```

GCP API を呼び出してリソース状態を検証します（作成処理は行いません）。

### 4. リソース作成

```bash
make bootstrap
```

`CONFIRM_BEFORE_APPLY="true"` の場合、実行前に確認プロンプトが表示されます。

### 5. Terraform Cloud 設定値の確認

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

これらの値を Terraform Cloud Workspace の Environment Variables に設定してください。

---

## 次のステップ

→ [Step 2: Terraform Cloud セットアップ](./02-tfc-setup.md) — TFC の Organization / Workspace を準備し、上記の環境変数を設定します。

---

## 詳細リファレンス

- [scripts/README.md](../../scripts/README.md)
- [docs/project-bootstrap/bootstrap.md](../project-bootstrap/bootstrap.md)
- [docs/project-bootstrap/architecture.md](../project-bootstrap/architecture.md)
