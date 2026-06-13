# shellcheck shell=bash
runtime_sa_email() {
  echo "$(runtime_sa_id)@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"
}
