# shellcheck shell=bash
# print-env / check で使う「runtime secret 1 件の状態表示」ヘルパ。
# 引数:
#   $1: secret 名 (例: tfc-notification-secret)
#   $2: 未設定時のヒント (例: "→ make setup-router-hmac")
print_runtime_secret_status() {
  local name="$1"
  local hint="${2:-}"
  if runtime_secret_exists "${name}"; then
    local versions
    versions=$(runtime_secret_version_count "${name}")
    printf "  %-30s ✓ configured (versions: %s)\n" "${name}" "${versions}"
  else
    if [[ -n "${hint}" ]]; then
      printf "  %-30s ✗ 未設定  %s\n" "${name}" "${hint}"
    else
      printf "  %-30s ✗ 未設定\n" "${name}"
    fi
  fi
}
