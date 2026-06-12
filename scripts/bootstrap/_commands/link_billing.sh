# shellcheck shell=bash
link_billing() {
  info "Linking Billing Account ${BILLING_ACCOUNT_ID} to ${BOOTSTRAP_PROJECT_ID}..."

  local current
  current="$(gcloud billing projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(billingAccountName)' 2>/dev/null || true)"

  if [[ "${current}" == "billingAccounts/${BILLING_ACCOUNT_ID}" ]]; then
    info "Billing Account already linked. Skipping."
    return
  fi

  gcloud billing projects link "${BOOTSTRAP_PROJECT_ID}" \
    --billing-account="${BILLING_ACCOUNT_ID}"

  info "Billing Account linked."
  propagate_sleep low "billing link to be effective for API enablement"
}
