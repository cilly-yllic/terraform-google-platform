# shellcheck shell=bash
# Terraform Cloud Workspace 用と (opt-in 時) GitHub Actions 用の
# 設定値を stdout に出力する。
# run_apply の末尾と run_print_env から呼ばれる。
print_env() {
  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local provider_full_name="projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/${WORKLOAD_IDENTITY_PROVIDER_ID}"

  echo "============================================"
  echo " Terraform Cloud Workspace Variables"
  echo "============================================"
  echo ""
  echo "TFC_GCP_PROVIDER_AUTH=true"
  echo "TFC_GCP_RUN_SERVICE_ACCOUNT_EMAIL=$(sa_email)"
  echo "TFC_GCP_WORKLOAD_PROVIDER_NAME=${provider_full_name}"
  echo "GOOGLE_PROJECT=${BOOTSTRAP_PROJECT_ID}"
  echo ""

  if [[ "${ENABLE_CLOUD_RUN_DEPLOY_SETUP:-false}" == "true" ]]; then
    local github_provider_full_name="projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/$(github_provider_id)"

    echo "============================================"
    echo " GitHub Actions Repository Variables / Secrets"
    echo "============================================"
    echo ""
    echo "# Set these as Repository Variables (or env vars in workflow):"
    echo "GCP_PROJECT_ID=${BOOTSTRAP_PROJECT_ID}"
    echo "GCP_WORKLOAD_IDENTITY_PROVIDER=${github_provider_full_name}"
    echo "GCP_DEPLOY_SERVICE_ACCOUNT=$(deploy_sa_email)"
    echo "GCP_RUNTIME_SERVICE_ACCOUNT=$(runtime_sa_email)"
    echo ""
    echo "# Usage in workflow (google-github-actions/auth@v2):"
    echo "#   - uses: google-github-actions/auth@v2"
    echo "#     with:"
    echo "#       workload_identity_provider: \${{ vars.GCP_WORKLOAD_IDENTITY_PROVIDER }}"
    echo "#       service_account: \${{ vars.GCP_DEPLOY_SERVICE_ACCOUNT }}"
    echo ""
  fi
}
