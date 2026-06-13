# shellcheck shell=bash
enable_cloud_run_deploy_apis() {
  info "Enabling Cloud Run deploy APIs on ${BOOTSTRAP_PROJECT_ID}..."
  gcloud services enable "${CLOUD_RUN_DEPLOY_APIS[@]}" \
    --project="${BOOTSTRAP_PROJECT_ID}"
  info "Cloud Run deploy APIs enabled."
  propagate_sleep med "newly-enabled APIs (run / artifactregistry / cloudbuild / secretmanager) to be ready"
}
