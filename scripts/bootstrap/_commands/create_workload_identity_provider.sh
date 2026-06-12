# shellcheck shell=bash
# Terraform Cloud 用 OIDC Provider を作成する。
# attribute condition で TFC Organization を縛り、別 org からの impersonate を防ぐ。
create_workload_identity_provider() {
  info "Creating Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID}..."
  if provider_exists; then
    info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} already exists. Skipping."
    return
  fi

  gcloud iam workload-identity-pools providers create-oidc "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --display-name="${WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME:-Terraform Cloud}" \
    --issuer-uri="${TFC_OIDC_ISSUER_URI}" \
    --allowed-audiences="${TFC_OIDC_ALLOWED_AUDIENCE}" \
    --attribute-mapping="\
google.subject=assertion.sub,\
attribute.terraform_organization=assertion.terraform_organization_name,\
attribute.terraform_project=assertion.terraform_project_name,\
attribute.terraform_workspace=assertion.terraform_workspace_name,\
attribute.terraform_run_phase=assertion.terraform_run_phase" \
    --attribute-condition="assertion.terraform_organization_name == \"${TFC_ORGANIZATION_NAME}\""

  info "Workload Identity Provider created."
  propagate_sleep low "WIF provider to be visible before SA binding"
}
