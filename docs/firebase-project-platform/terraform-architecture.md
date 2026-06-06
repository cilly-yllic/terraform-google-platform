# Terraform / GCP / Firebase 運用方針

## 概要

Terraform を利用して GCP Project、Firebase Project、および関連リソースを管理する。

認証は Service Account Key を使用せず、Workload Identity Federation (OIDC) を利用する。

複数サービスへの展開を見据え、Terraform 管理基盤を共通化する。

---

# 全体構成

```text
infra-bootstrap
├─ Workload Identity Pool
├─ terraform-project-factory
├─ terraform-nonprd
├─ terraform-{service_01}-prd
└─ terraform-{service_02}-prd
```

```text
Terraform Cloud
├─ project-factory
├─ {service_01}-dev
├─ {service_01}-stg
└─ {service_01}-prd
```

```text
GCP Projects
├─ {service_01}-dev
├─ {service_01}-stg
└─ {service_01}-prd
```

---

# Bootstrap Project

Terraform 管理用の専用 GCP Project を作成する。

```text
infra-bootstrap
```

この Project は複数サービス共通で利用する。

Bootstrap Project 自体は手動または gcloud により作成する。

Terraform による自己管理は行わない。

---

# Service Account 構成

## terraform-project-factory

用途:

- GCP Project 作成
- Billing Account 紐付け
- 初期 IAM 設定
- API 有効化

## terraform-nonprd

用途:

- dev 環境管理
- stg 環境管理

非本番環境を横断的に管理する。

## terraform-{service_02}-prd

用途:

- サービス単位の production 管理

Production はサービス単位で分離する。

---

# 認証方式

Service Account Key は使用しない。

```text
Terraform Cloud
↓
OIDC
↓
Workload Identity Pool
↓
Service Account Impersonation
↓
GCP
```

---

# Terraform 管理対象

- GCP Project
- Billing Association
- API Enablement
- Firebase Project
- IAM
- Service Account
- Firestore
- Cloud Storage
- Secret Manager
- Cloud Tasks
- Cloud Run 関連 IAM
- Cloud Functions 関連 IAM
- Data Connect 関連リソース

---

# Firebase 運用方針

## Terraform 管理対象

- Hosting Site 作成
- App Hosting Backend 作成

## Terraform 管理対象外

- Hosting Deploy
- Rewrites
- Redirects
- Headers
- GitHub Integration
- App Hosting の細かな設定

これらは Firebase CLI または設定ファイルで管理する。

---

# Workspace 構成

## project-factory

利用 SA:

```text
terraform-project-factory
```

## {service_01}-dev

利用 SA:

```text
terraform-nonprd
```

## {service_01}-stg

利用 SA:

```text
terraform-nonprd
```

## {service_01}-prd

利用 SA:

```text
terraform-{service_01}-prd
```

---

# 将来の拡張

新サービス追加時:

```text
another-service-dev
another-service-stg
another-service-prd
```

必要に応じて:

```text
terraform-another-service-prd
```

を作成する。

---

# 方針まとめ

- Terraform を採用する
- Bootstrap Project を共通利用する
- Production はサービス単位で分離する
- Non-Production は共通 Service Account で管理する
- 認証は OIDC / Workload Identity Federation を利用する
- Service Account Key は利用しない
- Firebase は初期構築のみ Terraform 管理する
- 頻繁に変更される Firebase 設定は CLI 管理とする
