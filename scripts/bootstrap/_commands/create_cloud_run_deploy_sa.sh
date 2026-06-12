# shellcheck shell=bash
create_cloud_run_deploy_sa() {
  info "Creating Cloud Run deploy SA $(deploy_sa_id)..."
  if deploy_sa_exists; then
    info "Deploy SA $(deploy_sa_email) already exists. Skipping."
    return
  fi

  gcloud iam service-accounts create "$(deploy_sa_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --display-name="${CLOUD_RUN_DEPLOY_SA_DISPLAY_NAME:-Cloud Run Router Deploy}"

  info "Deploy SA $(deploy_sa_email) created."
  propagate_sleep high "deploy SA to be visible to IAM before binding"
}
