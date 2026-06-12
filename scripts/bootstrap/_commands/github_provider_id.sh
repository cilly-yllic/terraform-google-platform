# shellcheck shell=bash
github_provider_id() {
  echo "${GITHUB_WIF_PROVIDER_ID:-github-actions}"
}
