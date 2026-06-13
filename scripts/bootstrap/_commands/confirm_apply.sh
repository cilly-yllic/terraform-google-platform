# shellcheck shell=bash
# 作成対象リソースの一覧を表示して、ユーザーに [y/N] 確認を求める。
# CONFIRM_BEFORE_APPLY=false なら確認をスキップする。
confirm_apply() {
  if [[ "${CONFIRM_BEFORE_APPLY:-true}" == "true" ]]; then
    echo ""
    echo "The following resources will be created (if not already present):"
    echo "  - GCP Project: ${BOOTSTRAP_PROJECT_ID}"
    echo "  - Billing link: ${BILLING_ACCOUNT_ID} -> ${BOOTSTRAP_PROJECT_ID}"
    echo "  - APIs: ${REQUIRED_APIS[*]}"
    echo "  - Service Account: $(sa_email)"
    echo "  - Workload Identity Pool: ${WORKLOAD_IDENTITY_POOL_ID}"
    echo "  - Workload Identity Provider: ${WORKLOAD_IDENTITY_PROVIDER_ID}"
    if [[ -n "${BUDGET_AMOUNT:-}" ]]; then
      echo "  - Budget: $(budget_display_name) (${BUDGET_AMOUNT} ${BUDGET_CURRENCY:-USD}, scope=${BUDGET_SCOPE:-project}, thresholds=${BUDGET_THRESHOLDS:-0.1,0.3,0.5,0.9,1.0})"
    else
      echo "  - Budget: (skipped — BUDGET_AMOUNT not set)"
    fi
    if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
      echo "  - Cloud Run runtime SA: $(runtime_sa_email)"
      echo "  - Cloud Run deploy SA: $(deploy_sa_email)"
      echo "  - GitHub WIF Provider: $(github_provider_id) (repo: ${GITHUB_REPOSITORY})"
      echo "  - Additional APIs: ${CLOUD_RUN_DEPLOY_APIS[*]}"
      echo "  - Runtime secret containers (empty): tfc-notification-secret, github-app-private-key"
    else
      echo "  - Cloud Run deploy resources: (skipped — ENABLE_CLOUD_RUN_DEPLOY_SETUP not set)"
    fi
    echo ""
    read -r -p "Proceed? [y/N] " answer
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
      info "Aborted."
      exit 0
    fi
  fi
}
