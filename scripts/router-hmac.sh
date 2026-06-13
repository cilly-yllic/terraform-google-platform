#!/usr/bin/env bash
#
# Cloud Run router の TFC HMAC shared secret 管理スクリプト。
#
# 用途:
#   - GCP Secret Manager の `tfc-notification-secret` を作成・rotate・sync
#   - 同じ値を Action A が読む各 project repo の GitHub Secret
#     `WEBHOOK_SECRET` にも同期 (`.env` の `WEBHOOK_SECRET_REPOS` で指定)
#
# usage: scripts/router-hmac.sh <setup|rotate|sync>
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

SECRET_NAME="tfc-notification-secret"
GH_SECRET_NAME="WEBHOOK_SECRET"

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

check_commands() {
  for cmd in gcloud openssl; do
    if ! command -v "${cmd}" &>/dev/null; then
      error "Required command not found: ${cmd}"
    fi
  done
  if [[ -n "${WEBHOOK_SECRET_REPOS:-}" ]] && ! command -v gh &>/dev/null; then
    error "WEBHOOK_SECRET_REPOS is set but 'gh' CLI not found. Install gh and run 'gh auth login'."
  fi
}

secret_exists() {
  gcloud secrets describe "${SECRET_NAME}" --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}

generate_hmac() {
  # 256-bit (32 bytes) → 64 文字の hex。HMAC-SHA512 用途として十分。
  openssl rand -hex 32
}

create_secret_container() {
  info "Creating Secret Manager container '${SECRET_NAME}' in ${BOOTSTRAP_PROJECT_ID}..."
  gcloud secrets create "${SECRET_NAME}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --replication-policy=automatic
}

add_secret_version() {
  local value="$1"
  info "Adding new version to '${SECRET_NAME}'..."
  printf '%s' "${value}" | gcloud secrets versions add "${SECRET_NAME}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --data-file=- > /dev/null
}

read_latest_value() {
  gcloud secrets versions access latest \
    --secret="${SECRET_NAME}" \
    --project="${BOOTSTRAP_PROJECT_ID}"
}

sync_to_github_repos() {
  local value="$1"
  if [[ -z "${WEBHOOK_SECRET_REPOS:-}" ]]; then
    info "WEBHOOK_SECRET_REPOS not set in .env — skipping GitHub Secret sync."
    info "  → 個別 repo に同期する場合: gh secret set ${GH_SECRET_NAME} --repo <owner/repo> --body \"\$VALUE\""
    return
  fi
  local repo
  for repo in ${WEBHOOK_SECRET_REPOS}; do
    info "Setting ${GH_SECRET_NAME} on GitHub repo: ${repo}"
    # gh secret set は stdin から値を取れる。--body- にすると argv に値が
    # 入らないので少し安全。
    printf '%s' "${value}" | gh secret set "${GH_SECRET_NAME}" --repo "${repo}" --body -
  done
}

cmd_setup() {
  load_env
  check_commands

  if secret_exists; then
    error "Secret '${SECRET_NAME}' already exists in ${BOOTSTRAP_PROJECT_ID}. Use 'rotate' to update or 'sync' to push existing value to new repos."
  fi

  local hmac
  hmac=$(generate_hmac)
  create_secret_container
  add_secret_version "${hmac}"
  sync_to_github_repos "${hmac}"
  info "Setup completed. HMAC stored in Secret Manager and synced to ${WEBHOOK_SECRET_REPOS:-(no repos)}"
}

cmd_rotate() {
  load_env
  check_commands

  if ! secret_exists; then
    error "Secret '${SECRET_NAME}' does not exist yet. Use 'setup' first."
  fi

  local hmac
  hmac=$(generate_hmac)
  add_secret_version "${hmac}"
  sync_to_github_repos "${hmac}"
  info "Rotation completed. New version added to Secret Manager and synced to ${WEBHOOK_SECRET_REPOS:-(no repos)}"
  info "  → Cloud Run service が新 version を参照するように redeploy も実行してください (revision を更新)"
}

cmd_sync() {
  load_env
  check_commands

  if ! secret_exists; then
    error "Secret '${SECRET_NAME}' does not exist yet. Use 'setup' first."
  fi
  if [[ -z "${WEBHOOK_SECRET_REPOS:-}" ]]; then
    error "WEBHOOK_SECRET_REPOS is not set in .env. Add it before running 'sync'."
  fi

  local hmac
  hmac=$(read_latest_value)
  sync_to_github_repos "${hmac}"
  info "Sync completed. Existing latest value pushed to ${WEBHOOK_SECRET_REPOS}"
}

show_help() {
  cat <<EOF
Usage: $0 <subcommand>

Manage the Cloud Run router's TFC HMAC shared secret.

SUBCOMMANDS
  setup    Initial creation: generate HMAC, create Secret Manager container,
           add first version, sync to WEBHOOK_SECRET_REPOS GitHub repos.
           Fails if the secret already exists.

  rotate   Generate a NEW HMAC, add as new version to the existing container,
           re-sync to WEBHOOK_SECRET_REPOS GitHub repos.

  sync     Read the existing latest version and push to WEBHOOK_SECRET_REPOS
           GitHub repos. Useful when adding a new repo to the list without
           rotating the secret.

ENVIRONMENT (loaded from .env)
  BOOTSTRAP_PROJECT_ID    GCP Project that holds Secret Manager (required)
  WEBHOOK_SECRET_REPOS    Space-separated list of GitHub repos
                          (e.g. "mooodone/svc1 mooodone/svc2") to which
                          WEBHOOK_SECRET should be synced. Optional for
                          'setup' / 'rotate', required for 'sync'.
EOF
}

main() {
  if [[ $# -lt 1 ]]; then
    show_help >&2
    exit 1
  fi
  case "$1" in
    setup)  cmd_setup ;;
    rotate) cmd_rotate ;;
    sync)   cmd_sync ;;
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
