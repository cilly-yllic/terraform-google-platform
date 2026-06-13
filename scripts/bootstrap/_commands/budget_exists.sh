# shellcheck shell=bash
# CLOUDSDK_CORE_DISABLE_PROMPTS で対話的な "API not enabled, enable now?" を
# 抑止 (billingbudgets.googleapis.com 未有効時に check が hang するのを防ぐ)。
# --project は quota/context project を pin して、ユーザーの選択中 project に
# 依存しないようにする。
budget_exists() {
  local existing
  existing="$(CLOUDSDK_CORE_DISABLE_PROMPTS=1 \
    gcloud billing budgets list \
      --billing-account="${BILLING_ACCOUNT_ID}" \
      --project="${BOOTSTRAP_PROJECT_ID}" \
      --filter="displayName=\"$(budget_display_name)\"" \
      --format='value(name)' 2>/dev/null || true)"
  [[ -n "${existing}" ]]
}
