# shellcheck shell=bash
project_exists() {
  gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" &>/dev/null
}
