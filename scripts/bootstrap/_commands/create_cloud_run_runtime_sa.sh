# shellcheck shell=bash
create_cloud_run_runtime_sa() {
  info "Creating Cloud Run runtime SA $(runtime_sa_id)..."
  if runtime_sa_exists; then
    info "Runtime SA $(runtime_sa_email) already exists. Skipping."
    return
  fi

  gcloud iam service-accounts create "$(runtime_sa_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --display-name="${CLOUD_RUN_RUNTIME_SA_DISPLAY_NAME:-Cloud Run Router Runtime}"

  info "Runtime SA $(runtime_sa_email) created."
  propagate_sleep high "runtime SA to be visible to IAM before binding"
}
