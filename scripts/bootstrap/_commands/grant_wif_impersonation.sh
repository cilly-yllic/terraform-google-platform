# shellcheck shell=bash
# TFC Organization (principalSet) → terraform-project-factory SA に
# workloadIdentityUser を付与し、impersonation を許可する。
grant_wif_impersonation() {
  info "Granting workloadIdentityUser to TFC organization ${TFC_ORGANIZATION_NAME}..."

  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local member="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/attribute.terraform_organization/${TFC_ORGANIZATION_NAME}"

  gcloud iam service-accounts add-iam-policy-binding "$(sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet

  info "WIF impersonation binding created."
}
