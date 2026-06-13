# shellcheck shell=bash
# Secret Manager の指定 secret の有効 version 数を返す (gcloud filter で
# state=ENABLED に絞ったうえで行数カウント)。存在しない / アクセスできない
# 場合は 0 を出力する。
runtime_secret_version_count() {
  local name="$1"
  gcloud secrets versions list "${name}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --filter='state=ENABLED' \
    --format='value(name)' 2>/dev/null | wc -l | tr -d ' '
}
