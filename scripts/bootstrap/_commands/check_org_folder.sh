# shellcheck shell=bash
# 配置 (placement) の決定:
#   - FOLDER_ID 直接指定        → folder mode
#   - FOLDER_NAME (+ ORG)       → folder mode (ensure_folder が find-or-create で
#                                 FOLDER_ID を解決)
#   - ORGANIZATION_ID のみ      → org-direct mode
# folder mode では folder が org に優先する (project 配置・IAM grant とも folder
# スコープ)。ORGANIZATION_ID は folder の親 / org-direct 時の配置先として使う。
check_org_folder() {
  info "Checking ORGANIZATION_ID / FOLDER_ID / FOLDER_NAME..."
  local org="${ORGANIZATION_ID:-}"
  local folder="${FOLDER_ID:-}"
  local folder_name="${FOLDER_NAME:-}"

  if [[ -n "${folder}" && -n "${folder_name}" ]]; then
    error "Both FOLDER_ID and FOLDER_NAME are set. Specify only one (FOLDER_ID = use as-is, FOLDER_NAME = find-or-create)."
  fi
  if [[ -n "${folder_name}" && -z "${org}" ]]; then
    error "FOLDER_NAME requires ORGANIZATION_ID (the parent organization to create/find the folder under)."
  fi
  if [[ -z "${org}" && -z "${folder}" && -z "${folder_name}" ]]; then
    error "None of ORGANIZATION_ID / FOLDER_ID / FOLDER_NAME is set. Specify a placement target."
  fi

  if [[ -n "${folder}" ]]; then
    info "Placement: FOLDER_ID=${folder} (folder mode)"
  elif [[ -n "${folder_name}" ]]; then
    info "Placement: FOLDER_NAME='${folder_name}' under org ${org} (folder mode; resolved by ensure_folder)"
  else
    info "Placement: ORGANIZATION_ID=${org} (org-direct mode)"
  fi
}
