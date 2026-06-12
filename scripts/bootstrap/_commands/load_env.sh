# shellcheck shell=bash
# `.env` をロードする。dispatcher の load_env 呼び出し時点で
# `${ENV_FILE}` は _constants.sh によって設定済み。
load_env() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    error ".env file not found at ${ENV_FILE}. Copy scripts/bootstrap.example.env to .env and fill in your values."
  fi
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
}
