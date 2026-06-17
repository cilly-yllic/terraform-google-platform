# shellcheck shell=bash
# FOLDER_NAME (display name) から FOLDER_ID を解決する。
#
# 動作:
#   1. FOLDER_ID が既に設定済み      → それを使う (何もしない)
#   2. FOLDER_NAME 未設定            → org 直下運用。何もしない
#   3. FOLDER_NAME 設定 (+ ORGANIZATION_ID 必須):
#        - org 配下から displayName 一致の folder を検索
#        - 見つかればその FOLDER_ID を採用
#        - 無ければ作成して FOLDER_ID を採用
#        - 解決した FOLDER_ID を `${ENV_FILE}` に書き戻す (再実行で 1 に落ちる)
#
# folder ID はプロジェクトと違い自分で指定できず GCP が自動採番するため、
# 「display name で find-or-create → 採番 ID を回収」という流れになる。
#
# 前提権限 (caller): org に対する resourcemanager.folders.list /
#   resourcemanager.folders.create (= roles/resourcemanager.folderCreator 等)。
#
# 解決後は FOLDER_ID が優先される (create_project は folder 配置、grant_iam は
# folder スコープ付与)。詳細: docs/project-bootstrap/design/iam-policy.md
ensure_folder() {
  # 1. 既に FOLDER_ID があるなら尊重する
  if [[ -n "${FOLDER_ID:-}" ]]; then
    info "FOLDER_ID already set (${FOLDER_ID}). Skipping folder resolution."
    return
  fi

  # 2. FOLDER_NAME 未指定 → org 直下運用
  if [[ -z "${FOLDER_NAME:-}" ]]; then
    return
  fi

  # 3. FOLDER_NAME 指定 → 親 org が必須
  if [[ -z "${ORGANIZATION_ID:-}" ]]; then
    error "FOLDER_NAME='${FOLDER_NAME}' is set but ORGANIZATION_ID (parent) is not. Set ORGANIZATION_ID."
  fi

  info "Resolving folder by display name '${FOLDER_NAME}' under organization ${ORGANIZATION_ID}..."

  local matches count
  matches="$(_folder_ids_by_display_name)"
  count="$(printf '%s' "${matches}" | grep -c . || true)"

  if [[ "${count}" -gt 1 ]]; then
    error "Multiple folders named '${FOLDER_NAME}' under organization ${ORGANIZATION_ID}. Set FOLDER_ID explicitly to disambiguate."
  fi

  if [[ "${count}" -eq 1 ]]; then
    FOLDER_ID="${matches#folders/}"
    info "Found existing folder '${FOLDER_NAME}': ${FOLDER_ID}"
  else
    info "Folder '${FOLDER_NAME}' not found. Creating under organization ${ORGANIZATION_ID}..."
    gcloud resource-manager folders create \
      --display-name="${FOLDER_NAME}" \
      --organization="${ORGANIZATION_ID}"
    propagate_sleep med "folder to be visible after creation"
    FOLDER_ID="$(_folder_ids_by_display_name)"
    FOLDER_ID="${FOLDER_ID#folders/}"
    [[ -n "${FOLDER_ID}" ]] || error "Failed to resolve FOLDER_ID after creating folder '${FOLDER_NAME}'."
    info "Folder created: ${FOLDER_ID}"
  fi

  export FOLDER_ID
  _persist_folder_id_to_env
}

# org 配下の displayName 一致 folder の resource name (folders/NNN) を改行区切りで返す。
_folder_ids_by_display_name() {
  gcloud resource-manager folders list \
    --organization="${ORGANIZATION_ID}" \
    --filter="displayName=\"${FOLDER_NAME}\"" \
    --format="value(name)" 2>/dev/null || true
}

# 解決した FOLDER_ID を ${ENV_FILE} に upsert する (既存行は置換、無ければ追記)。
_persist_folder_id_to_env() {
  [[ -f "${ENV_FILE}" ]] || return 0
  if grep -qE '^[[:space:]]*FOLDER_ID=' "${ENV_FILE}"; then
    local tmp
    tmp="$(mktemp)"
    sed -E "s|^[[:space:]]*FOLDER_ID=.*|FOLDER_ID=\"${FOLDER_ID}\"|" "${ENV_FILE}" > "${tmp}" && mv "${tmp}" "${ENV_FILE}"
  else
    printf '\nFOLDER_ID="%s"\n' "${FOLDER_ID}" >> "${ENV_FILE}"
  fi
  info "Persisted FOLDER_ID=${FOLDER_ID} to ${ENV_FILE}"
}