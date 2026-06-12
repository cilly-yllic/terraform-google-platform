# shellcheck shell=bash
# principalSet で GitHub repo を identity スコープに指定し、
# deploy SA の workloadIdentityUser として binding する。
# attribute.repository は WIF Provider 側の attribute mapping で
# assertion.repository から抽出された値。
grant_github_wif_binding() {
  info "Granting workloadIdentityUser to GitHub repo ${GITHUB_REPOSITORY}..."

  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local member="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${GITHUB_REPOSITORY}"

  gcloud iam service-accounts add-iam-policy-binding "$(deploy_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet

  info "GitHub WIF binding created."
}
