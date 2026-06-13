# shellcheck shell=bash
sa_exists() {
  gcloud iam service-accounts describe "$(sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}
