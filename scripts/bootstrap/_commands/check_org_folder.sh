# shellcheck shell=bash
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
