# shellcheck shell=bash
# `--dry-run` mode: GCP API を呼ばずに環境変数の充足状況を表示する。
# .env のみで完結する自己診断。
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
