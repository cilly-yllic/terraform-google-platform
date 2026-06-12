# shellcheck shell=bash
create_workload_identity_pool() {
  info "Creating Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID}..."
  if pool_exists; then
    info "Workload Identity Pool ${WORKLOAD_IDENTITY_POOL_ID} already exists. Skipping."
    return
  fi

  gcloud iam workload-identity-pools create "${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --display-name="${WORKLOAD_IDENTITY_POOL_DISPLAY_NAME:-Terraform Cloud}"

  info "Workload Identity Pool created."
  propagate_sleep med "WIF pool to be ready for provider creation"
}
