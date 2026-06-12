# shellcheck shell=bash
create_service_account() {
  info "Creating Service Account ${TERRAFORM_PROJECT_FACTORY_SA_ID}..."
  if sa_exists; then
    info "Service Account $(sa_email) already exists. Skipping."
    return
  fi

  gcloud iam service-accounts create "${TERRAFORM_PROJECT_FACTORY_SA_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --display-name="${TERRAFORM_PROJECT_FACTORY_SA_DISPLAY_NAME:-Terraform Project Factory}"

  info "Service Account $(sa_email) created."
  propagate_sleep high "SA to be visible to IAM before adding policy bindings"
}
