#!/usr/bin/env bash
#
# 任意の billing account に Terraform Project Factory SA を `roles/billing.user`
# として bind する thin script。
#
# 主な用途:
#   - **別 org の billing account** (reseller / shared billing 等) を新たに
#     使う場合: bootstrap の org-level grant では届かないので個別 grant が必要
#   - **per-account 厳格化** したい運用: bootstrap の org-level billing.user を
#     外して、必要 billing account だけ個別 grant したい場合 (上位 grant_iam.sh
#     の挙動を変える必要あり)
#
# 通常運用 (bootstrap の org-level grant で全 org-owned billing をカバー) では
# このスクリプトは不要。
#
# usage: make grant-billing BILLING=01XXXX-XXXXXX-XXXXXX
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BOOTSTRAP_DIR="${SCRIPT_DIR}/bootstrap"
ENV_FILE="${REPO_ROOT}/.env"

# Reuse log / SA helper functions from bootstrap.
# shellcheck source=bootstrap/_commands/_log.sh
source "${BOOTSTRAP_DIR}/_commands/_log.sh"
# shellcheck source=bootstrap/_commands/sa_id.sh
source "${BOOTSTRAP_DIR}/_commands/sa_id.sh"
# shellcheck source=bootstrap/_commands/sa_email.sh
source "${BOOTSTRAP_DIR}/_commands/sa_email.sh"

usage() {
  cat >&2 <<EOF
usage: make grant-billing BILLING=<billing-account-id>

Grants \`roles/billing.user\` on the specified billing account to the
Terraform Project Factory SA configured in .env.

  BILLING   billing account ID (例: 01CAAA-CF1712-505329)

Requires .env with BOOTSTRAP_PROJECT_ID and TERRAFORM_PROJECT_FACTORY_SA_ID set.
EOF
  exit 1
}

main() {
  local billing="${BILLING:-${1:-}}"
  if [[ -z "${billing}" ]]; then
    usage
  fi

  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env not found at ${ENV_FILE}. Run 'make bootstrap' first (or copy bootstrap.example.env)."
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  if [[ -z "${BOOTSTRAP_PROJECT_ID:-}" || -z "${TERRAFORM_PROJECT_FACTORY_SA_ID:-}" ]]; then
    error "BOOTSTRAP_PROJECT_ID / TERRAFORM_PROJECT_FACTORY_SA_ID must be set in .env."
  fi

  local sa member
  sa="$(sa_email)"
  member="serviceAccount:${sa}"

  info "Granting roles/billing.user on billingAccounts/${billing} to ${sa}..."
  gcloud billing accounts add-iam-policy-binding "${billing}" \
    --member="${member}" \
    --role="roles/billing.user" \
    --quiet > /dev/null
  info "Done."
}

main "$@"
