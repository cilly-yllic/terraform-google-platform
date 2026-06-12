# shellcheck shell=bash
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
