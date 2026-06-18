#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env.billing"

# --- Required environment variables ---
REQUIRED_VARS=(
  BILLING_DISPLAY_NAME
  MASTER_BILLING_ACCOUNT_ID
)

###############################################################################
# Utility
###############################################################################

info()  { echo "[INFO]  $*"; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; exit 1; }

###############################################################################
# Load .env.billing
###############################################################################

load_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env.billing file not found at ${ENV_FILE}. Copy scripts/create-billing-account.example.env to .env.billing and fill in your values."
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
}

###############################################################################
# Validation
###############################################################################

check_commands() {
  info "Checking required commands..."
  if ! command -v gcloud &>/dev/null; then
    error "Required command not found: gcloud"
  fi
  info "All required commands are available."
}

check_gcloud_auth() {
  info "Checking gcloud authentication..."
  if ! gcloud auth print-access-token &>/dev/null; then
    error "Not authenticated with gcloud. Run: gcloud auth login"
  fi
  info "gcloud is authenticated."
}

check_required_vars() {
  info "Checking required environment variables..."
  local missing=()
  for var in "${REQUIRED_VARS[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("${var}")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    error "Missing required environment variables: ${missing[*]}"
  fi
  info "All required environment variables are set."
}

check_master_billing_account() {
  info "Checking Master Billing Account ${MASTER_BILLING_ACCOUNT_ID}..."
  if ! gcloud billing accounts describe "${MASTER_BILLING_ACCOUNT_ID}" &>/dev/null; then
    error "Master Billing Account ${MASTER_BILLING_ACCOUNT_ID} not found or not accessible."
  fi
  info "Master Billing Account ${MASTER_BILLING_ACCOUNT_ID} exists and is accessible."
}

check_organization() {
  if [[ -n "${ORGANIZATION_ID:-}" ]]; then
    info "Checking Organization ${ORGANIZATION_ID}..."
    if ! gcloud organizations describe "${ORGANIZATION_ID}" &>/dev/null; then
      error "Organization ${ORGANIZATION_ID} not found or not accessible."
    fi
    info "Organization ${ORGANIZATION_ID} exists."
  fi
}

###############################################################################
# Resource existence helpers
###############################################################################

billing_account_exists() {
  # If a previously created ID is recorded, check by ID directly
  if [[ -n "${CREATED_BILLING_ACCOUNT_ID:-}" ]]; then
    gcloud billing accounts describe "${CREATED_BILLING_ACCOUNT_ID}" &>/dev/null
    return $?
  fi
  local accounts
  accounts="$(gcloud billing accounts list \
    --filter="displayName=\"${BILLING_DISPLAY_NAME}\" AND masterBillingAccount=\"billingAccounts/${MASTER_BILLING_ACCOUNT_ID}\"" \
    --format='value(name)' 2>/dev/null || true)"
  [[ -n "${accounts}" ]]
}

get_billing_account_id() {
  # If a previously created ID is recorded, return it directly
  if [[ -n "${CREATED_BILLING_ACCOUNT_ID:-}" ]]; then
    echo "${CREATED_BILLING_ACCOUNT_ID}"
    return
  fi
  local result
  result="$(gcloud billing accounts list \
    --filter="displayName=\"${BILLING_DISPLAY_NAME}\" AND masterBillingAccount=\"billingAccounts/${MASTER_BILLING_ACCOUNT_ID}\"" \
    --format='value(name)' 2>/dev/null || true)"
  echo "${result}" | head -n 1 | sed 's|billingAccounts/||'
}

###############################################################################
# check subcommand
###############################################################################

run_check() {
  check_commands
  check_gcloud_auth
  check_required_vars
  check_master_billing_account
  check_organization

  info "Checking if Billing Account '${BILLING_DISPLAY_NAME}' already exists..."
  if billing_account_exists; then
    local existing_id
    existing_id="$(get_billing_account_id)"
    info "Billing Account '${BILLING_DISPLAY_NAME}' already exists: ${existing_id}"
  else
    info "Billing Account '${BILLING_DISPLAY_NAME}' does not exist (will be created on apply)."
  fi

  info "Check completed."
}

###############################################################################
# apply subcommand
###############################################################################

confirm_apply() {
  if [[ "${CONFIRM_BEFORE_APPLY:-true}" == "true" ]]; then
    echo ""
    echo "The following resource will be created (if not already present):"
    echo "  - Billing Account: ${BILLING_DISPLAY_NAME}"
    echo "  - Master Billing Account: ${MASTER_BILLING_ACCOUNT_ID}"
    if [[ -n "${ORGANIZATION_ID:-}" ]]; then
      echo "  - Organization: ${ORGANIZATION_ID}"
    fi
    echo ""
    read -r -p "Proceed? [y/N] " answer
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
      info "Aborted."
      exit 0
    fi
  fi
}

create_billing_account() {
  info "Creating Billing Account '${BILLING_DISPLAY_NAME}'..."
  if billing_account_exists; then
    local existing_id
    existing_id="$(get_billing_account_id)"
    info "Billing Account '${BILLING_DISPLAY_NAME}' already exists: ${existing_id}. Skipping."
    return
  fi

  local cmd=(
    gcloud billing accounts create
    --display-name="${BILLING_DISPLAY_NAME}"
    --master-billing-account="${MASTER_BILLING_ACCOUNT_ID}"
  )

  if [[ -n "${ORGANIZATION_ID:-}" ]]; then
    cmd+=(--organization="${ORGANIZATION_ID}")
  fi

  local output
  output="$("${cmd[@]}" --format='value(name)')"
  echo "${output}"

  # Persist created billing account ID for robust idempotency
  # gcloud billing accounts create --format='value(name)' outputs: billingAccounts/XXXXXX-XXXXXX-XXXXXX
  local created_id
  created_id="$(echo "${output}" | sed -n 's|^billingAccounts/||p' | head -n 1)"
  if [[ -z "${created_id}" ]]; then
    # Fallback: extract ID pattern from raw output
    created_id="$(echo "${output}" | grep -oE '[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}' | head -n 1 || true)"
  fi
  if [[ -n "${created_id}" ]]; then
    {
      echo ""
      echo "# Created by create-billing-account.sh ($(date -Iseconds))"
      echo "CREATED_BILLING_ACCOUNT_ID=\"${created_id}\""
    } >> "${ENV_FILE}"
    CREATED_BILLING_ACCOUNT_ID="${created_id}"
    info "Persisted CREATED_BILLING_ACCOUNT_ID=${created_id} to ${ENV_FILE}"
  fi

  info "Billing Account '${BILLING_DISPLAY_NAME}' created."
}

run_apply() {
  check_commands
  check_gcloud_auth
  check_required_vars
  check_master_billing_account
  check_organization

  confirm_apply

  create_billing_account

  info "Billing Account creation completed."
  echo ""
  print_env
}

###############################################################################
# print-env subcommand
###############################################################################

print_env() {
  local billing_account_id
  if billing_account_exists; then
    billing_account_id="$(get_billing_account_id)"
  else
    error "Billing Account '${BILLING_DISPLAY_NAME}' does not exist. Run 'apply' first."
  fi

  echo "============================================"
  echo " Billing Account Information"
  echo "============================================"
  echo ""
  echo "BOOTSTRAP_BILLING_ACCOUNT_ID=${billing_account_id}"
  echo "BILLING_DISPLAY_NAME=${BILLING_DISPLAY_NAME}"
  echo "MASTER_BILLING_ACCOUNT_ID=${MASTER_BILLING_ACCOUNT_ID}"
  if [[ -n "${ORGANIZATION_ID:-}" ]]; then
    echo "ORGANIZATION_ID=${ORGANIZATION_ID}"
  fi
  echo ""
  echo "--------------------------------------------"
  echo " bootstrap.sh .env に設定する値:"
  echo "--------------------------------------------"
  echo ""
  echo "BOOTSTRAP_BILLING_ACCOUNT_ID=\"${billing_account_id}\""
  echo ""
}

run_print_env() {
  check_commands
  check_gcloud_auth
  check_required_vars

  print_env
}

###############################################################################
# --help
###############################################################################

show_help() {
  cat <<'EOF'
Usage: scripts/create-billing-account.sh [OPTIONS] <SUBCOMMAND>

Create a GCP Billing Account under a master billing account.

This script uses `gcloud billing accounts create` to provision a new
sub-billing account. The created billing account ID can then be used
in the bootstrap script (.env BOOTSTRAP_BILLING_ACCOUNT_ID).

SUBCOMMANDS
  check       Verify prerequisites (commands, auth, env vars, existing
              billing accounts). No changes are made.
  apply       Create the billing account (idempotent). Runs check
              first, then creates if not already present.
  print-env   Print the created billing account ID and related values
              for use in bootstrap.

OPTIONS
  -h, --help      Show this help message and exit.
  -d, --dry-run   Self-check mode: display environment variable status
                  and configuration summary without calling any GCP API.
  -i, --init      Generate a .env.billing template from
                  scripts/create-billing-account.example.env.
                  Interactive by default; use --init=env or --init=envrc
                  to skip the prompt.

ENVIRONMENT VARIABLES (loaded from .env.billing)
  Required:
    BILLING_DISPLAY_NAME                 Display name for the new billing account
    MASTER_BILLING_ACCOUNT_ID            Master (parent) billing account ID

  Optional:
    ORGANIZATION_ID                      GCP Organization numeric ID to link
    CONFIRM_BEFORE_APPLY                 Prompt before apply (default: true)

PREREQUISITES
  - gcloud CLI installed and authenticated (`gcloud auth login`)
  - Master billing account must exist and be accessible
  - The executing user must have `billing.accounts.create` permission
    on the master billing account (typically requires
    `billing.resellerCustomers.create` or Billing Account Creator role)

EXAMPLES
  # Show this help
  scripts/create-billing-account.sh --help

  # Generate .env.billing template
  scripts/create-billing-account.sh --init

  # Self-check environment variables
  scripts/create-billing-account.sh --dry-run

  # Run full check (calls GCP APIs)
  scripts/create-billing-account.sh check

  # Create billing account
  scripts/create-billing-account.sh apply

  # Print billing account ID for bootstrap
  scripts/create-billing-account.sh print-env

See also: docs/project-bootstrap/create-billing-account.md
EOF
}

###############################################################################
# --dry-run
###############################################################################

mask_value() {
  local val="$1"
  if [[ -z "${val}" ]]; then
    echo "(not set)"
    return
  fi
  local len=${#val}
  if [[ ${len} -le 4 ]]; then
    echo "****"
  else
    echo "${val:0:2}***${val: -2}"
  fi
}

run_dry_run() {
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    source "${ENV_FILE}"
    echo "[INFO]  Loaded .env.billing from ${ENV_FILE}"
  else
    echo "[WARN]  .env.billing file not found at ${ENV_FILE}. Showing current shell environment only."
  fi

  echo ""
  echo "============================================"
  echo " Required Variables"
  echo "============================================"
  local all_ok=true
  for var in "${REQUIRED_VARS[@]}"; do
    local val="${!var:-}"
    if [[ -n "${val}" ]]; then
      printf "  %-45s %s\n" "${var}" "$(mask_value "${val}")"
    else
      printf "  %-45s %s\n" "${var}" "** MISSING **"
      all_ok=false
    fi
  done

  echo ""
  echo "============================================"
  echo " Optional Variables"
  echo "============================================"
  local optional_vars=(
    "ORGANIZATION_ID|GCP Organization ID to link the billing account"
    "CONFIRM_BEFORE_APPLY|Prompt before apply (default: true)"
  )
  for entry in "${optional_vars[@]}"; do
    local var="${entry%%|*}"
    local desc="${entry#*|}"
    local val="${!var:-}"
    if [[ -n "${val}" ]]; then
      printf "  %-45s %s\n" "${var}" "${val}"
    else
      printf "  %-45s %s  — %s\n" "${var}" "(not set)" "${desc}"
    fi
  done

  echo ""
  if [[ "${all_ok}" == "true" ]]; then
    echo "[INFO]  All required variables are set. Ready to run 'check' or 'apply'."
  else
    echo "[WARN]  Some variables are missing or misconfigured. Fix the issues above before running 'check' or 'apply'."
    return 1
  fi
}

###############################################################################
# --init
###############################################################################

run_init() {
  local target_format="${1:-}"
  local template="${SCRIPT_DIR}/create-billing-account.example.env"

  if [[ ! -f "${template}" ]]; then
    error "Template file not found: ${template}"
  fi

  # Determine output format
  if [[ -z "${target_format}" ]]; then
    # Interactive prompt
    echo "Select output format:"
    echo "  1) .env.billing    (KEY=\"value\" — source .env.billing)"
    echo "  2) .envrc.billing  (export KEY=\"value\" — direnv)"
    read -r -p "Choice [1/2]: " choice
    case "${choice}" in
      1) target_format="env" ;;
      2) target_format="envrc" ;;
      *) error "Invalid choice: ${choice}" ;;
    esac
  fi

  local dest
  case "${target_format}" in
    env)
      dest="${REPO_ROOT}/.env.billing"
      ;;
    envrc)
      dest="${REPO_ROOT}/.envrc.billing"
      ;;
    *)
      error "Unknown format: ${target_format}. Use 'env' or 'envrc'."
      ;;
  esac

  # Guard existing file
  if [[ -f "${dest}" ]]; then
    error "${dest} already exists. Remove or rename it before running --init."
  fi

  if [[ "${target_format}" == "envrc" ]]; then
    # Convert to export format
    sed 's/^\([A-Za-z_][A-Za-z_0-9]*=\)/export \1/' "${template}" > "${dest}"
  else
    cp "${template}" "${dest}"
  fi

  info "Created ${dest} from ${template}"
  info "Edit the file and fill in your organization-specific values."
}

###############################################################################
# main
###############################################################################

main() {
  local subcommand=""
  local do_help=false
  local do_dry_run=false
  local do_init=false
  local init_format=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        do_help=true
        shift
        ;;
      -d|--dry-run)
        do_dry_run=true
        shift
        ;;
      --init=*)
        do_init=true
        init_format="${1#--init=}"
        shift
        ;;
      -i|--init)
        do_init=true
        shift
        ;;
      check|apply|print-env)
        subcommand="$1"
        shift
        ;;
      *)
        error "Unknown argument: $1. Run '$0 --help' for usage."
        ;;
    esac
  done

  # --help takes highest priority
  if [[ "${do_help}" == "true" ]]; then
    show_help
    exit 0
  fi

  # --init runs without loading .env.billing
  if [[ "${do_init}" == "true" ]]; then
    if [[ -n "${subcommand}" ]]; then
      echo "[WARN]  Subcommand '${subcommand}' is ignored when --init is specified." >&2
    fi
    run_init "${init_format}"
    exit 0
  fi

  # --dry-run does not require subcommand
  if [[ "${do_dry_run}" == "true" ]]; then
    if [[ -n "${subcommand}" ]]; then
      echo "[WARN]  Subcommand '${subcommand}' is ignored when --dry-run is specified." >&2
    fi
    run_dry_run
    exit $?
  fi

  # Subcommand required from here
  if [[ -z "${subcommand}" ]]; then
    echo "Error: subcommand required. Run '$0 --help' for usage." >&2
    echo "" >&2
    show_help >&2
    exit 1
  fi

  load_env

  case "${subcommand}" in
    check)
      run_check
      ;;
    apply)
      run_apply
      ;;
    print-env)
      run_print_env
      ;;
    *)
      error "Unknown subcommand: ${subcommand}. Run '$0 --help' for usage."
      ;;
  esac
}

main "$@"
