# shellcheck shell=bash
pool_exists() {
  gcloud iam workload-identity-pools describe "${WORKLOAD_IDENTITY_POOL_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" &>/dev/null
}
