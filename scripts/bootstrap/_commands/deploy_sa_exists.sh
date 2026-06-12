# shellcheck shell=bash
deploy_sa_exists() {
  gcloud iam service-accounts describe "$(deploy_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}
