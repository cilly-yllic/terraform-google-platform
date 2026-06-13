# shellcheck shell=bash
check_billing_account() {
  info "Checking Billing Account ${BILLING_ACCOUNT_ID}..."
  if ! gcloud billing accounts describe "${BILLING_ACCOUNT_ID}" &>/dev/null; then
    error "Billing Account ${BILLING_ACCOUNT_ID} not found or not accessible."
  fi
  info "Billing Account ${BILLING_ACCOUNT_ID} exists."
}
