# shellcheck shell=bash
# Bootstrap script の定数と配列を集約。
# `scripts/bootstrap.sh` (dispatcher) から最初に source される。
#
# `${REPO_ROOT}` は dispatcher 側で設定されている前提。

# --- Paths ---
ENV_FILE="${REPO_ROOT}/.env"

# --- OIDC Issuer (固定値) ---
# TFC / GitHub Actions の audience は **指定しない**: GCP default
# (provider full resource URI) を採用する。詳細は
# scripts/bootstrap/_commands/create_workload_identity_provider.sh の
# ヘッダコメント参照。
TFC_OIDC_ISSUER_URI="https://app.terraform.io"
GITHUB_OIDC_ISSUER_URI="https://token.actions.githubusercontent.com"

# --- Factory workspace 命名規約 ---
# Factory SA (terraform-project-factory) を impersonate できるのは「この prefix
# で始まる TFC workspace」だけに限定する (WIF provider の派生属性
# `terraform_workspace_kind` 経由)。dispatch-project-bootstrap action の
# workspace 名 default (`project-factory-{service}`) と一致させること。
# consumer が workspace 命名を変える場合は .env で上書きする。
# 詳細: docs/project-bootstrap/design/wif-attribute-mapping.md
FACTORY_WORKSPACE_PREFIX="${FACTORY_WORKSPACE_PREFIX:-project-factory-}"

# --- Required APIs (常に有効化される) ---
# orgpolicy は set_skip_default_network_policy() が `gcloud org-policies set-policy`
# を叩く際の quota project (= bootstrap project) で必要。core 化したので
# CLOUD_RUN_DEPLOY_APIS からは除いた (cloud-run opt-in の有無に関わらず使う)。
REQUIRED_APIS=(
  cloudresourcemanager.googleapis.com
  serviceusage.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  sts.googleapis.com
  cloudbilling.googleapis.com
  billingbudgets.googleapis.com
  orgpolicy.googleapis.com
)

# --- Additional APIs for cloud-run-router deploy ---
# ENABLE_CLOUD_RUN_DEPLOY_SETUP=true の場合のみ有効化される。
CLOUD_RUN_DEPLOY_APIS=(
  run.googleapis.com
  artifactregistry.googleapis.com
  cloudbuild.googleapis.com
  secretmanager.googleapis.com
)

# --- Required environment variables ---
REQUIRED_VARS=(
  BOOTSTRAP_PROJECT_ID
  BOOTSTRAP_PROJECT_NAME
  BOOTSTRAP_BILLING_ACCOUNT_ID
  TERRAFORM_PROJECT_FACTORY_SA_ID
  WORKLOAD_IDENTITY_POOL_ID
  WORKLOAD_IDENTITY_PROVIDER_ID
  TFC_ORGANIZATION_NAME
)
