#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

# --- Fixed values ---
TFC_OIDC_ISSUER_URI="https://app.terraform.io"
TFC_OIDC_ALLOWED_AUDIENCE="https://app.terraform.io"

GITHUB_OIDC_ISSUER_URI="https://token.actions.githubusercontent.com"

# --- Required APIs ---
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
# Enabled only when ENABLE_CLOUD_RUN_DEPLOY_SETUP=true.
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

# Sleep to absorb GCP eventual-consistency propagation.
#   high → 10s (critical: SA create → IAM binding)
#   med  → 5s  (moderate: API enable → next API call, WIF pool → provider)
#   low  → 1s  (minor: project create, billing link, WIF provider → IAM)
propagate_sleep() {
  local level="$1"
  local reason="${2:-propagation}"
  local seconds
  case "${level}" in
    high) seconds=10 ;;
    med)  seconds=5 ;;
    low)  seconds=1 ;;
    *)    seconds=0 ;;
  esac
  if (( seconds > 0 )); then
    info "Waiting ${seconds}s for ${reason}..."
    sleep "${seconds}"
  fi
}

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

  # Cloud Run deploy opt-in には GITHUB_REPOSITORY が必須
  # (WIF Provider の attribute condition で repo を絞り込むため)。
  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
      error "GITHUB_REPOSITORY is required when ENABLE_CLOUD_RUN_DEPLOY_SETUP=true (format: owner/repo)"
    fi
    if [[ ! "${GITHUB_REPOSITORY}" =~ ^[^/]+/[^/]+$ ]]; then
      error "GITHUB_REPOSITORY must be in 'owner/repo' format, got: ${GITHUB_REPOSITORY}"
    fi
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

budget_display_name() {
  echo "${BUDGET_DISPLAY_NAME:-${BOOTSTRAP_PROJECT_NAME} Budget}"
}

budget_exists() {
  # Use CLOUDSDK_CORE_DISABLE_PROMPTS to avoid an interactive
  # "API not enabled, enable now?" prompt that would hang the script
  # when billingbudgets.googleapis.com is not yet enabled (e.g. during
  # `check` before `enable_apis` has run).
  # --project pins the quota/context project so the call does not
  # depend on the user's currently-selected gcloud config project.
  local existing
  existing="$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 \
    gcloud billing budgets list \
      --billing-account="${BILLING_ACCOUNT_ID}" \
      --project="${BOOTSTRAP_PROJECT_ID}" \
      --filter="displayName=\"$(budget_display_name)\"" \
      --format='value(name)' 2>/dev/null || true)"
  [[ -n "${existing}" ]]
}

# --- Cloud Run deploy resource helpers (opt-in) ---

deploy_sa_id() {
  echo "${CLOUD_RUN_DEPLOY_SA_ID:-cloud-run-router-deploy}"
}

deploy_sa_email() {
  echo "$(deploy_sa_id)@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"
}

deploy_sa_exists() {
  gcloud iam service-accounts describe "$(deploy_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}

runtime_sa_id() {
  echo "${CLOUD_RUN_RUNTIME_SA_ID:-cloud-run-router-runtime}"
}

runtime_sa_email() {
  echo "$(runtime_sa_id)@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"
}

runtime_sa_exists() {
  gcloud iam service-accounts describe "$(runtime_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}

github_provider_id() {
  echo "${GITHUB_WIF_PROVIDER_ID:-github-actions}"
}

github_provider_exists() {
  gcloud iam workload-identity-pools providers describe "$(github_provider_id)" \
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

  if [[ -n "${BUDGET_AMOUNT:-}" ]]; then
    if project_exists; then
      info "Checking Budget '$(budget_display_name)'..."
      if budget_exists; then
        info "Budget '$(budget_display_name)' already exists."
      else
        info "Budget '$(budget_display_name)' does not exist (will be created on apply)."
      fi
    else
      info "Budget check deferred: bootstrap project does not exist yet. '$(budget_display_name)' will be created on apply."
    fi
  else
    info "BUDGET_AMOUNT not set. Budget creation will be skipped on apply."
  fi

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    info "Checking Cloud Run runtime SA $(runtime_sa_id)..."
    if project_exists && runtime_sa_exists; then
      info "Runtime SA $(runtime_sa_email) exists."
    else
      info "Runtime SA $(runtime_sa_email) does not exist (will be created on apply)."
    fi

    info "Checking Cloud Run deploy SA $(deploy_sa_id)..."
    if project_exists && deploy_sa_exists; then
      info "Deploy SA $(deploy_sa_email) exists."
    else
      info "Deploy SA $(deploy_sa_email) does not exist (will be created on apply)."
    fi

    info "Checking GitHub WIF Provider $(github_provider_id)..."
    if project_exists && pool_exists && github_provider_exists; then
      info "GitHub WIF Provider $(github_provider_id) exists."
    else
      info "GitHub WIF Provider $(github_provider_id) does not exist (will be created on apply)."
    fi
  else
    info "ENABLE_CLOUD_RUN_DEPLOY_SETUP not set. Cloud Run deploy resource creation will be skipped on apply."
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
    if [[ -n "${BUDGET_AMOUNT:-}" ]]; then
      echo "  - Budget: $(budget_display_name) (${BUDGET_AMOUNT} ${BUDGET_CURRENCY:-USD}, scope=${BUDGET_SCOPE:-project}, thresholds=${BUDGET_THRESHOLDS:-0.1,0.3,0.5,0.9,1.0})"
    else
      echo "  - Budget: (skipped — BUDGET_AMOUNT not set)"
    fi
    if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
      echo "  - Cloud Run runtime SA: $(runtime_sa_email)"
      echo "  - Cloud Run deploy SA: $(deploy_sa_email)"
      echo "  - GitHub WIF Provider: $(github_provider_id) (repo: ${GITHUB_REPOSITORY})"
      echo "  - Additional APIs: ${CLOUD_RUN_DEPLOY_APIS[*]}"
    else
      echo "  - Cloud Run deploy resources: (skipped — ENABLE_CLOUD_RUN_DEPLOY_SETUP not set)"
    fi
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
  propagate_sleep low "project to be ready for billing/API operations"
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
  propagate_sleep low "billing link to be effective for API enablement"
}

enable_apis() {
  info "Enabling required APIs on ${BOOTSTRAP_PROJECT_ID}..."
  gcloud services enable "${REQUIRED_APIS[@]}" \
    --project="${BOOTSTRAP_PROJECT_ID}"
  info "APIs enabled."
  propagate_sleep med "newly-enabled APIs to be ready (iam / billingbudgets)"
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
  propagate_sleep high "SA to be visible to IAM before adding policy bindings"
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
  propagate_sleep med "WIF pool to be ready for provider creation"
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
  propagate_sleep low "WIF provider to be visible before SA binding"
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

create_budget() {
  if [[ -z "${BUDGET_AMOUNT:-}" ]]; then
    info "BUDGET_AMOUNT not set. Skipping Budget creation."
    return
  fi

  local display_name
  display_name="$(budget_display_name)"
  local currency="${BUDGET_CURRENCY:-USD}"
  local scope="${BUDGET_SCOPE:-project}"
  local thresholds="${BUDGET_THRESHOLDS:-0.1,0.3,0.5,0.9,1.0}"

  info "Creating Budget '${display_name}' (${BUDGET_AMOUNT} ${currency}, scope=${scope})..."

  if budget_exists; then
    info "Budget '${display_name}' already exists. Skipping."
    return
  fi

  local cmd=(
    gcloud billing budgets create
    --billing-account="${BILLING_ACCOUNT_ID}"
    --project="${BOOTSTRAP_PROJECT_ID}"
    --display-name="${display_name}"
    --budget-amount="${BUDGET_AMOUNT}${currency}"
  )

  local threshold
  IFS=',' read -ra threshold_arr <<< "${thresholds}"
  for threshold in "${threshold_arr[@]}"; do
    threshold="${threshold// /}"
    [[ -z "${threshold}" ]] && continue
    cmd+=(--threshold-rule="percent=${threshold}")
  done

  case "${scope}" in
    project)
      local project_number
      project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
        --format='value(projectNumber)')"
      cmd+=(--filter-projects="projects/${project_number}")
      ;;
    billing-account)
      : # No project filter -> whole billing account
      ;;
    *)
      error "Unknown BUDGET_SCOPE: ${scope}. Use 'project' or 'billing-account'."
      ;;
  esac

  "${cmd[@]}"

  info "Budget '${display_name}' created."
}

###############################################################################
# Cloud Run deploy resources (opt-in via ENABLE_CLOUD_RUN_DEPLOY_SETUP=true)
###############################################################################

enable_cloud_run_deploy_apis() {
  info "Enabling Cloud Run deploy APIs on ${BOOTSTRAP_PROJECT_ID}..."
  gcloud services enable "${CLOUD_RUN_DEPLOY_APIS[@]}" \
    --project="${BOOTSTRAP_PROJECT_ID}"
  info "Cloud Run deploy APIs enabled."
  propagate_sleep med "newly-enabled APIs (run / artifactregistry / cloudbuild / secretmanager) to be ready"
}

create_cloud_run_runtime_sa() {
  info "Creating Cloud Run runtime SA $(runtime_sa_id)..."
  if runtime_sa_exists; then
    info "Runtime SA $(runtime_sa_email) already exists. Skipping."
    return
  fi

  gcloud iam service-accounts create "$(runtime_sa_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --display-name="${CLOUD_RUN_RUNTIME_SA_DISPLAY_NAME:-Cloud Run Router Runtime}"

  info "Runtime SA $(runtime_sa_email) created."
  propagate_sleep high "runtime SA to be visible to IAM before binding"
}

create_cloud_run_deploy_sa() {
  info "Creating Cloud Run deploy SA $(deploy_sa_id)..."
  if deploy_sa_exists; then
    info "Deploy SA $(deploy_sa_email) already exists. Skipping."
    return
  fi

  gcloud iam service-accounts create "$(deploy_sa_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --display-name="${CLOUD_RUN_DEPLOY_SA_DISPLAY_NAME:-Cloud Run Router Deploy}"

  info "Deploy SA $(deploy_sa_email) created."
  propagate_sleep high "deploy SA to be visible to IAM before binding"
}

grant_cloud_run_deploy_iam() {
  info "Granting IAM roles to Cloud Run deploy / runtime SAs..."

  local deploy_member runtime_member
  deploy_member="serviceAccount:$(deploy_sa_email)"
  runtime_member="serviceAccount:$(runtime_sa_email)"

  # --- Deploy SA roles on bootstrap project ---
  #   run.developer            : Cloud Run service の deploy / 更新
  #   artifactregistry.writer  : container image を push
  #   cloudbuild.builds.editor : `gcloud builds submit` で Cloud Build job 発行
  #   storage.admin            : Cloud Build が source upload に GCS bucket を使う
  #   iam.serviceAccountTokenCreator
  #                            : runtime SA の token を発行 (Cloud Run service 起動時の impersonation)
  local deploy_project_roles=(
    roles/run.developer
    roles/artifactregistry.writer
    roles/cloudbuild.builds.editor
    roles/storage.admin
    roles/iam.serviceAccountTokenCreator
  )
  for role in "${deploy_project_roles[@]}"; do
    info "  Deploy SA / Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${deploy_member}" \
      --role="${role}" \
      --quiet
  done

  # --- Deploy SA → Runtime SA: serviceAccountUser ---
  # Cloud Run service の `--service-account=<runtime>` を指定するには、
  # deploy 主体が runtime SA に対して serviceAccountUser を持つ必要がある。
  info "  Deploy SA / Runtime SA: roles/iam.serviceAccountUser"
  gcloud iam service-accounts add-iam-policy-binding "$(runtime_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --member="${deploy_member}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

  # --- Runtime SA roles on bootstrap project ---
  #   secretmanager.secretAccessor :
  #     Cloud Run service が runtime で TFC_NOTIFICATION_SECRET /
  #     GITHUB_APP_PRIVATE_KEY / TFC_API_TOKEN 等を読む。
  local runtime_project_roles=(
    roles/secretmanager.secretAccessor
  )
  for role in "${runtime_project_roles[@]}"; do
    info "  Runtime SA / Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${runtime_member}" \
      --role="${role}" \
      --quiet
  done

  info "Cloud Run deploy IAM roles granted."
}

create_github_wif_provider() {
  info "Creating GitHub WIF Provider $(github_provider_id)..."
  if github_provider_exists; then
    info "GitHub WIF Provider $(github_provider_id) already exists. Skipping."
    return
  fi

  # 既存の WIF Pool (TFC 用) に追加で GitHub Actions 用 OIDC Provider を載せる。
  # - issuer は GitHub Actions 固定
  # - allowed-audiences は指定しない (= デフォルトは provider full resource name で
  #   google-github-actions/auth がそのまま使う形式)
  # - attribute condition で 1 つの repo に厳しく絞る
  gcloud iam workload-identity-pools providers create-oidc "$(github_provider_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --display-name="${GITHUB_WIF_PROVIDER_DISPLAY_NAME:-GitHub Actions}" \
    --issuer-uri="${GITHUB_OIDC_ISSUER_URI}" \
    --attribute-mapping="\
google.subject=assertion.sub,\
attribute.repository=assertion.repository,\
attribute.repository_owner=assertion.repository_owner,\
attribute.ref=assertion.ref,\
attribute.actor=assertion.actor,\
attribute.workflow=assertion.workflow" \
    --attribute-condition="assertion.repository == \"${GITHUB_REPOSITORY}\""

  info "GitHub WIF Provider created."
  propagate_sleep low "WIF provider to be visible before SA binding"
}

grant_github_wif_binding() {
  info "Granting workloadIdentityUser to GitHub repo ${GITHUB_REPOSITORY}..."

  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  # principalSet で GitHub repo を identity スコープに指定。
  # attribute.repository は WIF Provider 側の attribute mapping で
  # assertion.repository から抽出された値。
  local member="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_REPOSITORY}"

  gcloud iam service-accounts add-iam-policy-binding "$(deploy_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet

  info "GitHub WIF binding created."
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
  create_budget

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    info "ENABLE_CLOUD_RUN_DEPLOY_SETUP=true — provisioning Cloud Run deploy resources..."
    enable_cloud_run_deploy_apis
    create_cloud_run_runtime_sa
    create_cloud_run_deploy_sa
    grant_cloud_run_deploy_iam
    create_github_wif_provider
    grant_github_wif_binding
  fi

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

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    local github_provider_full_name="projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/$(github_provider_id)"

    echo "============================================"
    echo " GitHub Actions Repository Variables / Secrets"
    echo "============================================"
    echo ""
    echo "# Set these as Repository Variables (or env vars in workflow):"
    echo "GCP_PROJECT_ID=${BOOTSTRAP_PROJECT_ID}"
    echo "GCP_WORKLOAD_IDENTITY_PROVIDER=${github_provider_full_name}"
    echo "GCP_DEPLOY_SERVICE_ACCOUNT=$(deploy_sa_email)"
    echo "GCP_RUNTIME_SERVICE_ACCOUNT=$(runtime_sa_email)"
    echo ""
    echo "# Usage in workflow (google-github-actions/auth@v2):"
    echo "#   - uses: google-github-actions/auth@v2"
    echo "#     with:"
    echo "#       workload_identity_provider: \${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}"
    echo "#       service_account: \${{ vars.GCP_DEPLOY_SERVICE_ACCOUNT }}"
    echo ""
  fi
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
Identity Federation resources required by the project-bootstrap module.

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

  Optional (Budget — created only when BUDGET_AMOUNT is set):
    BUDGET_AMOUNT                        Monthly budget amount (e.g. 1000).
                                         Budget is created only when set.
    BUDGET_CURRENCY                      Budget currency (default: USD)
    BUDGET_DISPLAY_NAME                  Budget display name
                                         (default: "${BOOTSTRAP_PROJECT_NAME} Budget")
    BUDGET_SCOPE                         'project' (default) — monitors
                                         BOOTSTRAP_PROJECT_ID only.
                                         'billing-account' — monitors entire
                                         billing account.
    BUDGET_THRESHOLDS                    Comma-separated alert thresholds as
                                         fractions (default:
                                         0.1,0.3,0.5,0.9,1.0)

  Optional (Cloud Run deploy — created only when
   ENABLE_CLOUD_RUN_DEPLOY_SETUP=true):
    ENABLE_CLOUD_RUN_DEPLOY_SETUP        Set to 'true' to provision GitHub
                                         WIF Provider + deploy/runtime SAs
                                         for cloud-run-router. Default: false.
    GITHUB_REPOSITORY                    'owner/repo' allowed to authenticate
                                         via the GitHub WIF Provider.
                                         Required when ENABLE_CLOUD_RUN_DEPLOY_SETUP=true.
    CLOUD_RUN_DEPLOY_SA_ID               Deploy SA ID
                                         (default: cloud-run-router-deploy)
    CLOUD_RUN_DEPLOY_SA_DISPLAY_NAME     Deploy SA display name
                                         (default: Cloud Run Router Deploy)
    CLOUD_RUN_RUNTIME_SA_ID              Runtime SA ID
                                         (default: cloud-run-router-runtime)
    CLOUD_RUN_RUNTIME_SA_DISPLAY_NAME    Runtime SA display name
                                         (default: Cloud Run Router Runtime)
    GITHUB_WIF_PROVIDER_ID               GitHub OIDC Provider ID
                                         (default: github-actions)
    GITHUB_WIF_PROVIDER_DISPLAY_NAME     Provider display name
                                         (default: GitHub Actions)

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
    "BUDGET_AMOUNT|Monthly budget amount (e.g. 1000). Budget is created only when set"
    "BUDGET_CURRENCY|Budget currency (default: USD)"
    "BUDGET_DISPLAY_NAME|Budget display name (default: \${BOOTSTRAP_PROJECT_NAME} Budget)"
    "BUDGET_SCOPE|Budget scope: 'project' (default) or 'billing-account'"
    "BUDGET_THRESHOLDS|Comma-separated alert thresholds (default: 0.1,0.3,0.5,0.9,1.0)"
    "ENABLE_CLOUD_RUN_DEPLOY_SETUP|Set 'true' to provision Cloud Run deploy resources (default: false)"
    "GITHUB_REPOSITORY|owner/repo allowed via GitHub WIF (required when ENABLE_CLOUD_RUN_DEPLOY_SETUP=true)"
    "CLOUD_RUN_DEPLOY_SA_ID|Deploy SA ID (default: cloud-run-router-deploy)"
    "CLOUD_RUN_DEPLOY_SA_DISPLAY_NAME|Deploy SA display name (default: Cloud Run Router Deploy)"
    "CLOUD_RUN_RUNTIME_SA_ID|Runtime SA ID (default: cloud-run-router-runtime)"
    "CLOUD_RUN_RUNTIME_SA_DISPLAY_NAME|Runtime SA display name (default: Cloud Run Router Runtime)"
    "GITHUB_WIF_PROVIDER_ID|GitHub OIDC Provider ID (default: github-actions)"
    "GITHUB_WIF_PROVIDER_DISPLAY_NAME|GitHub Provider display name (default: GitHub Actions)"
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
