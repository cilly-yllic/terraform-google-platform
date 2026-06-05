# Step 0: Billing Account 作成

`scripts/create-billing-account.sh` を使用して、master billing account 配下に新規 Billing Account を作成します。

> **前提**: Master Billing Account (Reseller / Channel Partner) を持つ場合のみ利用可能です。既存の Billing Account を使用する場合はこの Step をスキップし、[Step 1: Bootstrap](./01-bootstrap.md) へ進んでください。

---

## 前提条件

- `gcloud` CLI がインストール済み
- `gcloud auth login` で認証済み
- Master Billing Account に対する `billing.accounts.create` 権限（Billing Account Creator role または Reseller 権限）

---

## 手順

### 1. 環境変数ファイルの準備

```bash
# テンプレートからコピー
cp scripts/create-billing-account.example.env .env.billing
vi .env.billing
```

または `--init` オプションで生成:

```bash
scripts/create-billing-account.sh --init          # 対話形式
scripts/create-billing-account.sh --init=env      # 非対話 (.env.billing)
scripts/create-billing-account.sh --init=envrc    # 非対話 (.envrc.billing / direnv 向け)
```

設定する環境変数:

| 変数名 | 必須 | 説明 |
|--------|:---:|------|
| `BILLING_DISPLAY_NAME` | Yes | 新規 Billing Account の表示名 |
| `MASTER_BILLING_ACCOUNT_ID` | Yes | 親となる Master Billing Account ID |
| `ORGANIZATION_ID` | — | 紐付ける GCP Organization の数値 ID |
| `CONFIRM_BEFORE_APPLY` | — | `apply` 前の確認プロンプト (default: `true`) |

### 2. 事前確認

```bash
make create-billing-account-check
```

コマンド・認証状態・環境変数・master billing account のアクセス可否を確認します。

### 3. Billing Account 作成

```bash
make create-billing-account
```

### 4. 作成結果の確認

```bash
make create-billing-account-print-env
```

出力例:

```text
BILLING_ACCOUNT_ID=ABCDEF-123456-GHIJKL
```

この `BILLING_ACCOUNT_ID` を次の Step で使用します。

---

## 次のステップ

→ [Step 1: Bootstrap](./01-bootstrap.md) — 出力された `BILLING_ACCOUNT_ID` を `.env` に設定して bootstrap を実行します。

---

## 詳細リファレンス

- [scripts/README.md](../../scripts/README.md)
- [docs/project-bootstrap/create-billing-account.md](../project-bootstrap/create-billing-account.md)
