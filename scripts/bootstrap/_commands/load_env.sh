# shellcheck shell=bash
# `.env` をロードする。dispatcher の load_env 呼び出し時点で
# `${ENV_FILE}` は _constants.sh によって設定済み。
load_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env file not found at ${ENV_FILE}. Copy scripts/bootstrap.example.env to .env and fill in your values."
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"

  # backward-compat: 旧変数名 (prefix 無し) を新名 (BOOTSTRAP_*) にマップする。
  # DEPRECATED — 次の major で削除予定。既存 .env が旧名のままでも動くようにし、
  # 新名が未設定の時だけ旧名から引き継いで警告する。
  _alias_legacy_env() { # $1=old $2=new
    if [[ -n "${!1:-}" && -z "${!2:-}" ]]; then
      echo "[WARN]  .env: '${1}' は非推奨です。'${2}' に改名してください (今回は自動マップ)。" >&2
      export "${2}"="${!1}"
    fi
  }
  _alias_legacy_env BILLING_ACCOUNT_ID BOOTSTRAP_BILLING_ACCOUNT_ID
  _alias_legacy_env FOLDER_NAME BOOTSTRAP_FOLDER_NAME
  _alias_legacy_env FOLDER_ID BOOTSTRAP_FOLDER_ID
}
