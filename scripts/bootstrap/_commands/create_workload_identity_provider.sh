# shellcheck shell=bash
# Terraform Cloud 用 OIDC Provider を作成する。
#
# Audience 設計:
#   `--allowed-audiences` は **指定しない**。GCP はこのとき
#   `//iam.googleapis.com/projects/{project_number}/locations/global/workloadIdentityPools/{pool}/providers/{provider}`
#   (provider の full resource URI) を default audience として accept する。
#   TFC の Dynamic Credentials も `TFC_GCP_PROVIDER_AUDIENCE` 未設定時は
#   `TFC_GCP_WORKLOAD_PROVIDER_NAME` から同じ URI を自動的に組み立てて `aud`
#   に乗せるので、両者が default で一致する。
#
#   この方が:
#     - audience が provider 単位で unique → 別 GCP project の WIF provider に
#       token を replay されない (cross-audience replay 防止)
#     - Action 側で別途 env var を set しなくてよい (= 設定漏れによる
#       audience mismatch のバグの種が消える)
#   かつての default だった `https://app.terraform.io` は TFC 共通の generic
#   値で provider unique 性が無く、Action 側 env var の明示的 set 漏れにより
#   400 invalid_grant を踏みやすかったため、廃止した。
#
# attribute condition で TFC Organization を縛り、別 org からの impersonate を防ぐ。
create_workload_identity_provider() {
  info "Creating Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID}..."
  if provider_exists; then
    # 既存 provider が legacy 設定 (`--allowed-audiences=https://app.terraform.io` 等)
    # を持っていたら、default audience に揃えるため clear する。Action A が
    # `TFC_GCP_PROVIDER_AUDIENCE` を set しない仕様と整合させる migration step。
    local current_audiences
    current_audiences="$(gcloud iam workload-identity-pools providers describe "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
      --project="${BOOTSTRAP_PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
      --format="value(oidc.allowedAudiences)" 2>/dev/null || true)"
    if [[ -n "${current_audiences}" ]]; then
      info "  Existing provider has legacy allowed-audiences (${current_audiences}). Clearing to use GCP default (provider full resource URI)..."
      gcloud iam workload-identity-pools providers update-oidc "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
        --project="${BOOTSTRAP_PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
        --clear-allowed-audiences > /dev/null
      info "  Allowed-audiences cleared."
    else
      info "Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID} already exists. Skipping."
    fi
    return
  fi

  gcloud iam workload-identity-pools providers create-oidc "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --display-name="${WORKLOAD_IDENTITY_PROVIDER_DISPLAY_NAME:-Terraform Cloud}" \
    --issuer-uri="${TFC_OIDC_ISSUER_URI}" \
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
