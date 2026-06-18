# Billing Account 作成ガイド

## 概要

この script は、`gcloud billing accounts create` を使用して GCP Billing Account を master billing account 配下に新規作成するためのものです。

作成した Billing Account ID は、bootstrap script (`.env` の `BOOTSTRAP_BILLING_ACCOUNT_ID`) に設定して使用します。

## 前提条件

- `gcloud` CLI がインストール済みであること
- `gcloud auth login` で認証済みであること
- 以下の権限を持つアカウントで実行すること:
  - Master Billing Account に対する `billing.accounts.create`
  - 典型的には **Billing Account Creator** role または reseller 権限 (`billing.resellerCustomers.create`) が必要

> **注意**: master billing account を持たない通常の利用者はこのスクリプトを使用できません。Reseller / Channel Partner アカウントを持つ場合のみ利用可能です。README にてこの制約を明記しています。

## 実行手順

### 1. 環境変数ファイルの準備

```bash
cp scripts/create-billing-account.example.env .env.billing
vi .env.billing
```

または `--init` オプションで生成:

```bash
scripts/create-billing-account.sh --init          # 対話形式で .env.billing / .envrc.billing を選択
scripts/create-billing-account.sh --init=env      # 非対話で .env.billing を生成
scripts/create-billing-account.sh --init=envrc    # 非対話で .envrc.billing を生成 (direnv 向け)
```

`.env.billing` に以下の値を設定してください:

| 変数名 | 必須 | 説明 |
|--------|:---:|------|
| `BILLING_DISPLAY_NAME` | ✓ | 新規 Billing Account の表示名 |
| `MASTER_BILLING_ACCOUNT_ID` | ✓ | 親となる Master Billing Account ID |
| `ORGANIZATION_ID` | — | 紐付ける GCP Organization の数値 ID |
| `CONFIRM_BEFORE_APPLY` | — | `apply` 前の確認プロンプト (default: `true`) |

### 2. 事前確認

```bash
make create-billing-account-check
```

必要なコマンド、認証状態、環境変数、master billing account のアクセス可否を確認します。作成処理は行いません。

### 3. Billing Account 作成

```bash
make create-billing-account
```

以下を順に実行します:

1. 入力値検証
2. Master Billing Account の存在確認
3. Organization の存在確認 (設定時)
4. 同名 Billing Account の重複チェック
5. Billing Account 作成
6. 作成された Billing Account ID の出力

`CONFIRM_BEFORE_APPLY="true"` の場合、実行前に確認プロンプトが表示されます。

### 4. 作成結果の確認

```bash
make create-billing-account-print-env
```

出力例:

```text
============================================
 Billing Account Information
============================================

BOOTSTRAP_BILLING_ACCOUNT_ID=ABCDEF-123456-GHIJKL
BILLING_DISPLAY_NAME=My Project Billing
MASTER_BILLING_ACCOUNT_ID=XXXXXX-XXXXXX-XXXXXX

--------------------------------------------
 bootstrap.sh .env に設定する値:
--------------------------------------------

BOOTSTRAP_BILLING_ACCOUNT_ID="ABCDEF-123456-GHIJKL"
```

## bootstrap への連携

`make create-billing-account-print-env` の出力にある `BOOTSTRAP_BILLING_ACCOUNT_ID` の値を `scripts/bootstrap.example.env` (または `.env`) の `BOOTSTRAP_BILLING_ACCOUNT_ID` に設定してください。

```bash
# .env (bootstrap 用)
BOOTSTRAP_BILLING_ACCOUNT_ID="ABCDEF-123456-GHIJKL"
```

その後、通常の bootstrap フローを実行:

```bash
make bootstrap-check
make bootstrap
```

## CLI オプション

| Option | Short | 説明 |
|--------|-------|------|
| `--help` | `-h` | Usage / subcommand / オプション / 環境変数の一覧表示 |
| `--dry-run` | `-d` | GCP API を呼び出さず、環境変数の充足状況と設定サマリーを表示 |
| `--init` | `-i` | `.env.billing` または `.envrc.billing` のテンプレートを生成 |
| `--init=env` | — | 非対話で `.env.billing` を生成 |
| `--init=envrc` | — | 非対話で `.envrc.billing` (direnv 用 `export` 形式) を生成 |

## トラブルシューティング

### Master Billing Account 権限不足

```text
ERROR: Master Billing Account XXXXXX-XXXXXX-XXXXXX not found or not accessible.
```

`gcloud auth login` で使用しているアカウントが master billing account に対して `billing.accounts.list` および `billing.accounts.create` 権限を持っているか確認してください。

### billing accounts create 失敗

```text
ERROR: (gcloud.billing.accounts.create) PERMISSION_DENIED
```

Master billing account に対する Billing Account Creator role が必要です。通常の GCP ユーザーではこの操作は実行できません。Reseller / Channel Partner アカウントが必要です。

### Organization 権限不足

```text
ERROR: Organization XXXXXXXXXXXX not found or not accessible.
```

`resourcemanager.organizations.get` 権限が必要です。Organization Viewer role などを確認してください。
