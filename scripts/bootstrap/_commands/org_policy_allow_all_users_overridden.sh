# shellcheck shell=bash
# bootstrap project に `iam.allowedPolicyMemberDomains` の project スコープ
# override (allowAll: true) が設定済みかを判定する。
#
# 判定ロジック:
#   `gcloud org-policies describe` は override が無い場合 NOT_FOUND を返す。
#   出力中に `allowAll: true` の文字列があれば override 済みとみなす。
#
# あくまで `make bootstrap-check` の自己診断用途。実際の override 適用は
# `override_org_policy_allow_all_users` (apply 時) が行う。
org_policy_allow_all_users_overridden() {
  local out
  if ! out="$(gcloud org-policies describe iam.allowedPolicyMemberDomains \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --format=yaml 2>/dev/null)"; then
    return 1
  fi
  [[ "${out}" == *"allowAll: true"* ]]
}
