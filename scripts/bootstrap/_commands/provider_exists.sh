# shellcheck shell=bash
provider_exists() {
  gcloud iam workload-identity-pools providers describe "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" &>/dev/null
}
