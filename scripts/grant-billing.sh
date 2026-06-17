#!/usr/bin/env bash
#
# billing account に Terraform Project Factory SA を `roles/billing.user`
# として bind する thin script。
#
# 主な用途:
#   - **folder mode** 運用: bootstrap は org-level billing.user を付けないため、
#     各サービスが使う billing account に Factory SA を個別 grant する必要がある。
#     `.env` の SERVICE_BILLING_ACCOUNT_IDS に列挙しておけば `make grant-billing`
#     一発で全部に付与できる。
#   - **別 org の billing account** (reseller / shared billing) を追加する場合。
#
# 対象 billing account の決め方 (上から優先):
#   1. `BILLING=<id>` (単発上書き。1 アカウントだけ grant)
#   2. `.env` の `SERVICE_BILLING_ACCOUNT_IDS` (空白区切りの複数 ID) を全件 grant
#
# usage:
#   make grant-billing                          # .env の SERVICE_BILLING_ACCOUNT_IDS 全件
#   make grant-billing BILLING=01XXXX-XXXXXX-XXXXXX   # 単発
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"
ENV_FILE="${REPO_ROOT}/.env"

# Reuse log / SA helper functions from bootstrap.
# (sa_email.sh は自己完結。sa_id.sh は存在しない/不要なので source しない)
# shellcheck source=bootstrap/_commands/_log.sh
source "${BOOTSTRAP_DIR}/_commands/_log.sh"
# shellcheck source=bootstrap/_commands/sa_email.sh
source "${BOOTSTRAP_DIR}/_commands/sa_email.sh"

usage() {
  cat >&2 <<EOF
usage:
  make grant-billing                                # .env の SERVICE_BILLING_ACCOUNT_IDS 全件
  make grant-billing BILLING=<billing-account-id>   # 単一 account のみ

Grants \`roles/billing.user\` on the billing account(s) to the Terraform
Project Factory SA configured in .env.

対象の決め方:
  BILLING                      単発上書き (例: 01CAAA-CF1712-505329)
  SERVICE_BILLING_ACCOUNT_IDS  .env の空白区切りリスト (BILLING 未指定時に全件 grant)

Requires .env with BOOTSTRAP_PROJECT_ID and TERRAFORM_PROJECT_FACTORY_SA_ID set.
EOF
  exit 1
}

main() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env not found at ${ENV_FILE}. Run 'make bootstrap' first (or copy bootstrap.example.env)."
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  if [[ -z "${BOOTSTRAP_PROJECT_ID:-}" || -z "${TERRAFORM_PROJECT_FACTORY_SA_ID:-}" ]]; then
    error "BOOTSTRAP_PROJECT_ID / TERRAFORM_PROJECT_FACTORY_SA_ID must be set in .env."
  fi

  # 付与対象 billing account を決定:
  #   1. BILLING / 第1引数 (単発上書き)
  #   2. .env の SERVICE_BILLING_ACCOUNT_IDS (空白区切り複数)
  local -a accounts=()
  local single="${BILLING:-${1:-}}"
  if [[ -n "${single}" ]]; then
    accounts=("${single}")
  elif [[ -n "${SERVICE_BILLING_ACCOUNT_IDS:-}" ]]; then
    read -r -a accounts <<< "${SERVICE_BILLING_ACCOUNT_IDS}"
  fi

  if [[ ${#accounts[@]} -eq 0 ]]; then
    error "No billing account specified. Set SERVICE_BILLING_ACCOUNT_IDS in .env or pass BILLING=<id>."
  fi

  local sa member billing
  sa="$(sa_email)"
  member="serviceAccount:${sa}"

  for billing in "${accounts[@]}"; do
    info "Granting roles/billing.user on billingAccounts/${billing} to ${sa}..."
    gcloud billing accounts add-iam-policy-binding "${billing}" \
      --member="${member}" \
      --role="roles/billing.user" \
      --quiet > /dev/null
  done
  info "Done (${#accounts[@]} billing account(s))."
}

main "$@"
