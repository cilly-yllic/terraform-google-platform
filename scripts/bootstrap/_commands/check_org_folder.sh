# shellcheck shell=bash
# 配置 (placement) の優先順位 (上が優先):
#   1. BOOTSTRAP_FOLDER_ID 直接指定        → folder mode (BOOTSTRAP_FOLDER_NAME が同時に在っても無視)
#   2. BOOTSTRAP_FOLDER_NAME (+ ORG)       → folder mode (ensure_folder が find-or-create で
#                                 BOOTSTRAP_FOLDER_ID を解決し .env に書き戻す)
#   3. ORGANIZATION_ID のみ      → org-direct mode
# folder mode では folder が org に優先する (project 配置・IAM grant とも folder
# スコープ)。ORGANIZATION_ID は folder の親 / org-direct 時の配置先として使う。
#
# 注: BOOTSTRAP_FOLDER_NAME 解決後は ensure_folder が BOOTSTRAP_FOLDER_ID を .env に書き戻すため、
# 再実行時は BOOTSTRAP_FOLDER_ID と BOOTSTRAP_FOLDER_NAME が「両方」セットされた状態になる。これは
# 正常系 (BOOTSTRAP_FOLDER_ID 優先で BOOTSTRAP_FOLDER_NAME は無視) であり、エラーにしない。
check_org_folder() {
  info "Checking ORGANIZATION_ID / BOOTSTRAP_FOLDER_ID / BOOTSTRAP_FOLDER_NAME..."
  local org="${ORGANIZATION_ID:-}"
  local folder="${BOOTSTRAP_FOLDER_ID:-}"
  local folder_name="${BOOTSTRAP_FOLDER_NAME:-}"

  if [[ -z "${org}" && -z "${folder}" && -z "${folder_name}" ]]; then
    error "None of ORGANIZATION_ID / BOOTSTRAP_FOLDER_ID / BOOTSTRAP_FOLDER_NAME is set. Specify a placement target."
  fi

  if [[ -n "${folder}" ]]; then
    info "Placement: BOOTSTRAP_FOLDER_ID=${folder} (folder mode)"
    if [[ -n "${folder_name}" ]]; then
      info "  (BOOTSTRAP_FOLDER_NAME='${folder_name}' is ignored because BOOTSTRAP_FOLDER_ID is set)"
    fi
  elif [[ -n "${folder_name}" ]]; then
    if [[ -z "${org}" ]]; then
      error "BOOTSTRAP_FOLDER_NAME requires ORGANIZATION_ID (the parent organization to create/find the folder under)."
    fi
    info "Placement: BOOTSTRAP_FOLDER_NAME='${folder_name}' under org ${org} (folder mode; resolved by ensure_folder)"
  else
    info "Placement: ORGANIZATION_ID=${org} (org-direct mode)"
  fi
}
