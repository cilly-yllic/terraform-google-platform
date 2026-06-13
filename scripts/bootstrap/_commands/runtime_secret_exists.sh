# shellcheck shell=bash
# Secret Manager に runtime secret が存在するかチェック。
runtime_secret_exists() {
  local name="$1"
  gcloud secrets describe "${name}" --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}
