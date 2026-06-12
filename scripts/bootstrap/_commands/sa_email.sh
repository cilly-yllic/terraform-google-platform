# shellcheck shell=bash
sa_email() {
  echo "${TERRAFORM_PROJECT_FACTORY_SA_ID}@${BOOTSTRAP_PROJECT_ID}.iam.gserviceaccount.com"
}
