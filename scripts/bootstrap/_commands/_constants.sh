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

# --- Required APIs (常に有効化される) ---
REQUIRED_APIS=(
  cloudresourcemanager.googleapis.com
  serviceusage.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  sts.googleapis.com
  cloudbilling.googleapis.com
  billingbudgets.googleapis.com
)

# --- Additional APIs for cloud-run-router deploy ---
# ENABLE_CLOUD_RUN_DEPLOY_SETUP=true の場合のみ有効化される。
# orgpolicy は override_org_policy_allow_all_users() が `gcloud org-policies
# set-policy` を叩くのに必要。
CLOUD_RUN_DEPLOY_APIS=(
  run.googleapis.com
  artifactregistry.googleapis.com
  cloudbuild.googleapis.com
  secretmanager.googleapis.com
  orgpolicy.googleapis.com
)

# --- Required environment variables ---
REQUIRED_VARS=(
  BOOTSTRAP_PROJECT_ID
  BOOTSTRAP_PROJECT_NAME
  BILLING_ACCOUNT_ID
  TERRAFORM_PROJECT_FACTORY_SA_ID
  WORKLOAD_IDENTITY_POOL_ID
  WORKLOAD_IDENTITY_PROVIDER_ID
  TFC_ORGANIZATION_NAME
)
