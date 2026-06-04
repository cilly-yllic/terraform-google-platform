#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# --- Fixed values ---
TFC_OIDC_ISSUER_URI="https://app.terraform.io"
TFC_OIDC_ALLOWED_AUDIENCE="https://app.terraform.io"

# --- Required APIs ---
REQUIRED_APIS=(
  cloudresourcemanager.googleapis.com
  serviceusage.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  sts.googleapis.com
  cloudbilling.googleapis.com
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

###############################################################################
# Utility
###############################################################################

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

###############################################################################
# Load .env
###############################################################################

load_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env file not found at ${ENV_FILE}. Copy scripts/bootstrap.example.env to .env and fill in your values."
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

check_org_folder() {
  info "Checking ORGANIZATION_ID / FOLDER_ID..."
  local org="${ORGANIZATION_ID:-}"
  local folder="${FOLDER_ID:-}"

  if [[ -n "${org}" && -n "${folder}" ]]; then
    error "Both ORGANIZATION_ID and FOLDER_ID are set. Specify only one."
  fi
  if [[ -z "${org}" && -z "${folder}" ]]; then
    error "Neither ORGANIZATION_ID nor FOLDER_ID is set. Specify one."
  fi
  if [[ -n "${org}" ]]; then
    info "Using ORGANIZATION_ID=${org}"
  else
    info "Using FOLDER_ID=${folder}"
  fi
}

check_billing_account() {
  info "Checking Billing Account ${BILLING_ACCOUNT_ID}..."
  if ! gcloud billing accounts describe "${BILLING_ACCOUNT_ID}" &>/dev/null; then
    error "Billing Account ${BILLING_ACCOUNT_ID} not found or not accessible."
  fi
  info "Billing Account ${BILLING_ACCOUNT_ID} exists."
}

###############################################################################
# Resource existence helpers
###############################################################################

project_exists() {
  gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}

sa_email() {
  echo "${TERRAFORM_PROJECT_FACTORY_SA_ID}@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"
}

sa_exists() {
  gcloud iam service-accounts describe "$(sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}

pool_exists() {
  gcloud iam workload-identity-pools describe "${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" &>/dev/null
}

provider_exists() {
  gcloud iam workload-identity-pools providers describe "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" &>/dev/null
}

###############################################################################
# check subcommand
###############################################################################

run_check() {
  check_commands
  check_gcloud_auth
  check_required_vars
  check_org_folder
  check_billing_account

  info "Checking Project ${BOOTSTRAP_PROJECT_ID}..."
  if project_exists; then
    info "Project ${BOOTSTRAP_PROJECT_ID} exists."
  else
    info "Project ${BOOTSTRAP_PROJECT_ID} does not exist (will be created on apply)."
  fi

  info "Checking Service Account ${TERRAFORM_PROJECT_FACTORY_SA_ID}..."
  if project_exists && sa_exists; then
    info "Service Account $(sa_email) exists."
  else
    info "Service Account $(sa_email) does not exist (will be created on apply)."
  fi

  info "Checking Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID}..."
  if project_exists && pool_exists; then
    info "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} exists."
  else
    info "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} does not exist (will be created on apply)."
  fi

  info "Checking Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID}..."
  if project_exists && pool_exists && provider_exists; then
    info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} exists."
  else
    info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} does not exist (will be created on apply)."
  fi

  info "Check completed."
}

###############################################################################
# apply subcommand
###############################################################################

confirm_apply() {
  if [[ "${CONFIRM_BEFORE_APPLY:-true}" == "true" ]]; then
    echo ""
    echo "The following resources will be created (if not already present):"
    echo "  - GCP Project: ${BOOTSTRAP_PROJECT_ID}"
    echo "  - Billing link: ${BILLING_ACCOUNT_ID} -> ${BOOTSTRAP_PROJECT_ID}"
    echo "  - APIs: ${REQUIRED_APIS[*]}"
    echo "  - Service Account: $(sa_email)"
    echo "  - Workload Identity Pool: ${WORKLOAD_IDENTITY_POOL_ID}"
    echo "  - Workload Identity Provider: ${WORKLOAD_IDENTITY_PROVIDER_ID}"
    echo ""
    read -r -p "Proceed? [y/N] " answer
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
      info "Aborted."
      exit 0
    fi
  fi
}

create_project() {
  info "Creating Project ${BOOTSTRAP_PROJECT_ID}..."
  if project_exists; then
    info "Project ${BOOTSTRAP_PROJECT_ID} already exists. Skipping."
    return
  fi

  local parent_flag
  if [[ -n "${FOLDER_ID:-}" ]]; then
    parent_flag="--folder=${FOLDER_ID}"
  else
    parent_flag="--organization=${ORGANIZATION_ID}"
  fi

  gcloud projects create "${BOOTSTRAP_PROJECT_ID}" \
    --name="${BOOTSTRAP_PROJECT_NAME}" \
    "${parent_flag}"

  info "Project ${BOOTSTRAP_PROJECT_ID} created."
}

link_billing() {
  info "Linking Billing Account ${BILLING_ACCOUNT_ID} to ${BOOTSTRAP_PROJECT_ID}..."

  local current
  current="$(gcloud billing projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(billingAccountName)' 2>/dev/null || true)"

  if [[ "${current}" == "billingAccounts/${BILLING_ACCOUNT_ID}" ]]; then
    info "Billing Account already linked. Skipping."
    return
  fi

  gcloud billing projects link "${BOOTSTRAP_PROJECT_ID}" \
    --billing-account="${BILLING_ACCOUNT_ID}"

  info "Billing Account linked."
}

enable_apis() {
  info "Enabling required APIs on ${BOOTSTRAP_PROJECT_ID}..."
  gcloud services enable "${REQUIRED_APIS[@]}" \
    --project="${BOOTSTRAP_PROJECT_ID}"
  info "APIs enabled."
}

create_service_account() {
  info "Creating Service Account ${TERRAFORM_PROJECT_FACTORY_SA_ID}..."
  if sa_exists; then
    info "Service Account $(sa_email) already exists. Skipping."
    return
  fi

  gcloud iam service-accounts create "${TERRAFORM_PROJECT_FACTORY_SA_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --display-name="${TERRAFORM_PROJECT_FACTORY_SA_DISPLAY_NAME:-Terraform Project Factory}"

  info "Service Account $(sa_email) created."
}

grant_iam() {
  info "Granting IAM roles to $(sa_email)..."

  local member
  member="serviceAccount:$(sa_email)"

  # --- Organization or Folder level ---
  if [[ -n "${ORGANIZATION_ID:-}" ]]; then
    local org_roles=(
      roles/resourcemanager.projectCreator
      roles/resourcemanager.projectIamAdmin
    )
    for role in "${org_roles[@]}"; do
      info "  Org: ${role}"
      gcloud organizations add-iam-policy-binding "${ORGANIZATION_ID}" \
        --member="${member}" \
        --role="${role}" \
        --quiet
    done
  else
    local folder_roles=(
      roles/resourcemanager.projectCreator
      roles/resourcemanager.projectIamAdmin
    )
    for role in "${folder_roles[@]}"; do
      info "  Folder: ${role}"
      gcloud resource-manager folders add-iam-policy-binding "${FOLDER_ID}" \
        --member="${member}" \
        --role="${role}" \
        --quiet
    done
  fi

  # --- Billing Account ---
  info "  Billing: roles/billing.user"
  gcloud billing accounts add-iam-policy-binding "${BILLING_ACCOUNT_ID}" \
    --member="${member}" \
    --role="roles/billing.user" \
    --quiet

  # --- infra-bootstrap Project ---
  local project_roles=(
    roles/iam.serviceAccountAdmin
    roles/iam.workloadIdentityPoolAdmin
  )
  for role in "${project_roles[@]}"; do
    info "  Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${member}" \
      --role="${role}" \
      --quiet
  done

  info "IAM roles granted."
}

create_workload_identity_pool() {
  info "Creating Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID}..."
  if pool_exists; then
    info "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} already exists. Skipping."
    return
  fi

  gcloud iam workload-identity-pools create "${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --display-name="${WORKLOAD_IDENTITY_POOL_DISPLAY_NAME:-Terraform Cloud}"

  info "Workload Identity Pool created."
}

create_workload_identity_provider() {
  info "Creating Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID}..."
  if provider_exists; then
    info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} already exists. Skipping."
    return
  fi

  gcloud iam workload-identity-pools providers create-oidc "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --display-name="${WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME:-Terraform Cloud}" \
    --issuer-uri="${TFC_OIDC_ISSUER_URI}" \
    --allowed-audiences="${TFC_OIDC_ALLOWED_AUDIENCE}" \
    --attribute-mapping="\
google.subject=assertion.sub,\
attribute.terraform_organization=assertion.terraform_organization_name,\
attribute.terraform_project=assertion.terraform_project_name,\
attribute.terraform_workspace=assertion.terraform_workspace_name,\
attribute.terraform_run_phase=assertion.terraform_run_phase" \
    --attribute-condition="assertion.terraform_organization_name == \"${TFC_ORGANIZATION_NAME}\""

  info "Workload Identity Provider created."
}

grant_wif_impersonation() {
  info "Granting workloadIdentityUser to TFC organization ${TFC_ORGANIZATION_NAME}..."

  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local member="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/attribute.terraform_organization/${TFC_ORGANIZATION_NAME}"

  gcloud iam service-accounts add-iam-policy-binding "$(sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet

  info "WIF impersonation binding created."
}

run_apply() {
  check_commands
  check_gcloud_auth
  check_required_vars
  check_org_folder
  check_billing_account

  confirm_apply

  create_project
  link_billing
  enable_apis
  create_service_account
  grant_iam
  create_workload_identity_pool
  create_workload_identity_provider
  grant_wif_impersonation

  info "Bootstrap apply completed."
  echo ""
  print_env
}

###############################################################################
# print-env subcommand
###############################################################################

print_env() {
  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local provider_full_name="projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/${WORKLOAD_IDENTITY_PROVIDER_ID}"

  echo "============================================"
  echo " Terraform Cloud Workspace Variables"
  echo "============================================"
  echo ""
  echo "TFC_GCP_PROVIDER_AUTH=true"
  echo "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL=$(sa_email)"
  echo "TFC_GCP_WORKLOAD_PROVIDER_NAME=${provider_full_name}"
  echo "GOOGLE_PROJECT=${BOOTSTRAP_PROJECT_ID}"
  echo ""
}

run_print_env() {
  check_commands
  check_gcloud_auth
  check_required_vars

  if ! project_exists; then
    error "Project ${BOOTSTRAP_PROJECT_ID} does not exist. Run 'make bootstrap' first."
  fi

  print_env
}

###############################################################################
# --help
###############################################################################

show_help() {
  cat <<'EOF'
Usage: scripts/bootstrap.sh [OPTIONS] <SUBCOMMAND>

Bootstrap the infra-bootstrap GCP Project, Service Account, and Workload
Identity Federation resources required by terraform-gcp-project-factory.

SUBCOMMANDS
  check       Verify prerequisites (commands, auth, env vars, existing
              GCP resources). No changes are made.
  apply       Create all bootstrap resources (idempotent). Runs check
              first, then creates missing resources.
  print-env   Print the Terraform Cloud Workspace variables to configure
              after a successful apply.

OPTIONS
  -h, --help      Show this help message and exit.
  -d, --dry-run   Self-check mode: display environment variable status
                  and configuration summary without calling any GCP API.
  -i, --init      Generate a .env or .envrc template from
                  scripts/bootstrap.example.env.
                  Interactive by default; use --init=env or --init=envrc
                  to skip the prompt.

ENVIRONMENT VARIABLES (loaded from .env)
  Required:
    BOOTSTRAP_PROJECT_ID                 GCP Project ID for bootstrap
    BOOTSTRAP_PROJECT_NAME               Display name for the project
    BILLING_ACCOUNT_ID                   Billing Account to link
    TERRAFORM_PROJECT_FACTORY_SA_ID      Service Account ID
    WORKLOAD_IDENTITY_POOL_ID            WIF Pool ID
    WORKLOAD_IDENTITY_PROVIDER_ID        WIF Provider ID
    TFC_ORGANIZATION_NAME                Terraform Cloud org name

  Required (one of):
    ORGANIZATION_ID                      Numeric org ID
    FOLDER_ID                            Numeric folder ID

  Optional:
    TERRAFORM_PROJECT_FACTORY_SA_DISPLAY_NAME
                                         SA display name
    WORKLOAD_IDENTITY_POOL_DISPLAY_NAME  Pool display name
    WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME
                                         Provider display name
    CONFIRM_BEFORE_APPLY                 Prompt before apply (default: true)

EXAMPLES
  # Show this help
  scripts/bootstrap.sh --help

  # Generate .env template
  scripts/bootstrap.sh --init

  # Self-check environment variables
  scripts/bootstrap.sh --dry-run

  # Run full check (calls GCP APIs)
  scripts/bootstrap.sh check

  # Create resources
  scripts/bootstrap.sh apply

  # Print TFC workspace variables
  scripts/bootstrap.sh print-env

See also: docs/bootstrap.md, scripts/README.md
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
    echo "[INFO]  Loaded .env from ${ENV_FILE}"
  else
    echo "[WARN]  .env file not found at ${ENV_FILE}. Showing current shell environment only."
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
  echo " Organization / Folder"
  echo "============================================"
  local org="${ORGANIZATION_ID:-}"
  local folder="${FOLDER_ID:-}"
  if [[ -n "${org}" && -n "${folder}" ]]; then
    echo "  [ERROR] Both ORGANIZATION_ID and FOLDER_ID are set. Specify only one."
    all_ok=false
  elif [[ -z "${org}" && -z "${folder}" ]]; then
    echo "  [WARN]  Neither ORGANIZATION_ID nor FOLDER_ID is set."
    echo "          -> Project cannot be created under an org or folder."
    all_ok=false
  elif [[ -n "${org}" ]]; then
    printf "  %-45s %s\n" "ORGANIZATION_ID" "$(mask_value "${org}")"
  else
    printf "  %-45s %s\n" "FOLDER_ID" "$(mask_value "${folder}")"
  fi

  echo ""
  echo "============================================"
  echo " Optional Variables"
  echo "============================================"
  local optional_vars=(
    "TERRAFORM_PROJECT_FACTORY_SA_DISPLAY_NAME|SA display name (default: Terraform Project Factory)"
    "WORKLOAD_IDENTITY_POOL_DISPLAY_NAME|Pool display name (default: Terraform Cloud)"
    "WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME|Provider display name (default: Terraform Cloud)"
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
  local template="${SCRIPT_DIR}/bootstrap.example.env"

  if [[ ! -f "${template}" ]]; then
    error "Template file not found: ${template}"
  fi

  # Determine output format
  if [[ -z "${target_format}" ]]; then
    # Interactive prompt
    echo "Select output format:"
    echo "  1) .env    (KEY=\"value\" — source .env)"
    echo "  2) .envrc  (export KEY=\"value\" — direnv)"
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
      dest="${REPO_ROOT}/.env"
      ;;
    envrc)
      dest="${REPO_ROOT}/.envrc"
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

  # --init runs without loading .env
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
