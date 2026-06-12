# shellcheck shell=bash
github_provider_exists() {
  gcloud iam workload-identity-pools providers describe "$(github_provider_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" &>/dev/null
}
