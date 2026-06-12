# shellcheck shell=bash
# Terraform Project Factory SA に必要な IAM role を付与する。
#   Organization / Folder : projectCreator + projectIamAdmin
#   Billing Account       : billing.user
#   Bootstrap Project     : serviceAccountAdmin + workloadIdentityPoolAdmin
grant_iam() {
  info "Granting IAM roles to $(sa_email)..."

  local member
  member="serviceAccount:$(sa_email)"

  # --- Organization or Folder level ---
  if [[ -n "${ORGANIZATION_ID:-}" ]]; then
    local org_roles=(
      roles/resourcemanager.projectCreator
      roles/resourcemanager.projectIamAdmin
    )
    for role in "${org_roles[@]}"; do
      info "  Org: ${role}"
      gcloud organizations add-iam-policy-binding "${ORGANIZATION_ID}" \
        --member="${member}" \
        --role="${role}" \
        --quiet
    done
  else
    local folder_roles=(
      roles/resourcemanager.projectCreator
      roles/resourcemanager.projectIamAdmin
    )
    for role in "${folder_roles[@]}"; do
      info "  Folder: ${role}"
      gcloud resource-manager folders add-iam-policy-binding "${FOLDER_ID}" \
        --member="${member}" \
        --role="${role}" \
        --quiet
    done
  fi

  # --- Billing Account ---
  info "  Billing: roles/billing.user"
  gcloud billing accounts add-iam-policy-binding "${BILLING_ACCOUNT_ID}" \
    --member="${member}" \
    --role="roles/billing.user" \
    --quiet

  # --- infra-bootstrap Project ---
  local project_roles=(
    roles/iam.serviceAccountAdmin
    roles/iam.workloadIdentityPoolAdmin
  )
  for role in "${project_roles[@]}"; do
    info "  Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${member}" \
      --role="${role}" \
      --quiet
  done

  info "IAM roles granted."
}
