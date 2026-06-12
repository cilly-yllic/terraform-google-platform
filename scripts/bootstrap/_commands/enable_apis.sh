# shellcheck shell=bash
enable_apis() {
  info "Enabling required APIs on ${BOOTSTRAP_PROJECT_ID}..."
  gcloud services enable "${REQUIRED_APIS[@]}" \
    --project="${BOOTSTRAP_PROJECT_ID}"
  info "APIs enabled."
  propagate_sleep med "newly-enabled APIs to be ready (iam / billingbudgets)"
}
