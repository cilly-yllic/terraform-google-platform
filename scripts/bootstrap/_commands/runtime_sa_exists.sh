# shellcheck shell=bash
runtime_sa_exists() {
  gcloud iam service-accounts describe "$(runtime_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}
