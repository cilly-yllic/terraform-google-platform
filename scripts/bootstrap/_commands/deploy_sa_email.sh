# shellcheck shell=bash
deploy_sa_email() {
  echo "$(deploy_sa_id)@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"
}
