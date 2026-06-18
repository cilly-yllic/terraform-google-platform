# shellcheck shell=bash
check_billing_account() {
  info "Checking Billing Account ${BOOTSTRAP_BILLING_ACCOUNT_ID}..."
  if ! gcloud billing accounts describe "${BOOTSTRAP_BILLING_ACCOUNT_ID}" &>/dev/null; then
    error "Billing Account ${BOOTSTRAP_BILLING_ACCOUNT_ID} not found or not accessible."
  fi
  info "Billing Account ${BOOTSTRAP_BILLING_ACCOUNT_ID} exists."
}
