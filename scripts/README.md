# scripts/

Bootstrap スクリプト群のリファレンス。メインスクリプトは [`bootstrap.sh`](bootstrap.sh)。

## bootstrap.sh

`infra-bootstrap` GCP Project / Service Account / Workload Identity Federation を構築するスクリプト。
Terraform Cloud が `terraform-project-factory` SA を OIDC 経由で impersonate できる状態を作ります。

詳細な背景・前提条件・トラブルシューティングは [docs/bootstrap.md](../docs/bootstrap.md) を参照してください。

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

---

## `.env` と `.envrc` の使い分け

| ファイル | ロード方法 | 用途 |
|---------|-----------|------|
| `.env` | `source .env` (bootstrap.sh が自動で読む) | 通常利用 |
| `.envrc` | `direnv allow` (シェル進入時に自動ロード) | [direnv](https://direnv.net/) 利用者向け |

`bootstrap.sh` は `.env` を自動で読み込みます。`.envrc` を使う場合は、`direnv allow` でシェルに変数をロードした状態でスクリプトを実行してください (`.env` が存在しない場合はシェル環境の変数を参照します)。

---

## 関連ドキュメント

- [docs/bootstrap.md](../docs/bootstrap.md) — 前提条件・実行手順の詳細・トラブルシューティング
- [docs/design/iam-policy.md](../docs/design/iam-policy.md) — IAM role 付与の設計根拠
- [docs/design/wif-attribute-mapping.md](../docs/design/wif-attribute-mapping.md) — WIF Attribute Mapping の詳細
