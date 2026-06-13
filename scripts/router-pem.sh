#!/usr/bin/env bash
#
# ============================================================================
# ⚠️  DEPRECATED
# ============================================================================
# This script is no longer the recommended flow.
#
# The deploy workflow now syncs GH_APP_PRIVATE_KEY from GitHub Secrets to GCP
# Secret Manager automatically on each deploy. GitHub Secret is the single
# source of truth.
#
# This script is retained for:
#   - Local development / debugging without going through GitHub
#   - Emergency direct PEM injection outside the deploy pipeline
#
# For the recommended flow, see scripts/README.md
# → "Cloud Run router runtime secrets" section
# ============================================================================
#
# Cloud Run router の GitHub App Private Key (PEM) 管理スクリプト。
#
# 用途:
#   - GCP Secret Manager の `github-app-private-key` を作成・新 version 追加
#   - 値は GitHub App 設定画面でダウンロードした `.pem` ファイル
#
# usage: scripts/router-pem.sh add <path/to/key.pem>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

SECRET_NAME="github-app-private-key"

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

load_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env not found at ${ENV_FILE}. Copy scripts/bootstrap.example.env to .env first."
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  if [[ -z "${BOOTSTRAP_PROJECT_ID:-}" ]]; then
    error "BOOTSTRAP_PROJECT_ID is required in .env"
  fi
}

secret_exists() {
  gcloud secrets describe "${SECRET_NAME}" --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}

cmd_add() {
  local pem_path="$1"
  if [[ ! -f "${pem_path}" ]]; then
    error "PEM file not found: ${pem_path}"
  fi
  # 軽い shape チェック (RSA / EC PEM 共通)。完全な検証は openssl rsa -check 等で。
  if ! head -1 "${pem_path}" | grep -q "BEGIN .* PRIVATE KEY"; then
    error "${pem_path} does not look like a PEM private key (missing '-----BEGIN ... PRIVATE KEY-----' header)"
  fi

  load_env

  if ! secret_exists; then
    info "Creating Secret Manager container '${SECRET_NAME}' in ${BOOTSTRAP_PROJECT_ID}..."
    gcloud secrets create "${SECRET_NAME}" \
      --project="${BOOTSTRAP_PROJECT_ID}" \
      --replication-policy=automatic
  fi

  info "Adding new version to '${SECRET_NAME}' from ${pem_path}..."
  gcloud secrets versions add "${SECRET_NAME}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --data-file="${pem_path}" > /dev/null

  info "PEM stored as new version of '${SECRET_NAME}'."
  info "  → Cloud Run service が新 version を参照するように redeploy も実行してください"
}

show_help() {
  cat <<EOF
Usage: $0 add <path/to/private-key.pem>

Register a GitHub App private key (PEM) in GCP Secret Manager as
'${SECRET_NAME}'. Creates the secret container on first run, otherwise
adds a new version.

ENVIRONMENT (loaded from .env)
  BOOTSTRAP_PROJECT_ID    GCP Project that holds Secret Manager (required)
EOF
}

print_deprecation_warning() {
  cat >&2 <<'EOF'

============================================================================
⚠️  DEPRECATED: scripts/router-pem.sh
============================================================================
The deploy workflow now syncs GH_APP_PRIVATE_KEY from GitHub Secrets to GCP
Secret Manager automatically on each deploy. GitHub Secret is the single
source of truth.

This script is retained as a fallback for local development / emergency
direct PEM injection. For the recommended flow, see scripts/README.md.
============================================================================

EOF
}

main() {
  if [[ $# -lt 1 ]]; then
    show_help >&2
    exit 1
  fi
  case "$1" in
    add)
      if [[ $# -lt 2 ]]; then
        error "PEM file path required. Usage: $0 add <path/to/key.pem>"
      fi
      print_deprecation_warning
      cmd_add "$2"
      ;;
    -h|--help|help) show_help ;;
    *)
      echo "[ERROR] Unknown subcommand: $1" >&2
      echo "" >&2
      show_help >&2
      exit 1
      ;;
  esac
}

main "$@"
