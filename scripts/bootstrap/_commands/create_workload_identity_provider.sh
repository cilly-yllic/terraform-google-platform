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
#
# 派生属性 `terraform_workspace_kind`:
#   workspace 名が ${FACTORY_WORKSPACE_PREFIX} で始まるか否かで "factory" / "service"
#   を導出する。Factory SA (org/folder の projectCreator+IamAdmin を持つ強権 SA) の
#   impersonation を「factory workspace だけ」に限定するために使う
#   (grant_wif_impersonation.sh)。これにより org 内の無関係 workspace
#   (firebase 設定用 {service}-{env} や実験 workspace) から Factory SA への
#   成り代わりを構造的に塞ぐ。per-env SA 側は attribute.terraform_workspace で
#   別途 workspace 限定 binding 済み。
#   詳細: docs/project-bootstrap/design/wif-attribute-mapping.md
create_workload_identity_provider() {
  info "Creating Workload Identity Provider ${WORKLOAD_IDENTITY_PROVIDER_ID}..."
  if provider_exists; then
    # 既存 provider が legacy 設定 (`--allowed-audiences=https://app.terraform.io` 等、
    # かつ provider full resource URI を含まないもの) を持っていたら、provider
    # full resource URI のみを受け入れる状態に張り替える。Action A が
    # `TFC_GCP_PROVIDER_AUDIENCE` を set しない仕様 (TFC default = resource URI)
    # と整合させる migration step。
    #
    # 注意: gcloud `update-oidc` には `--clear-allowed-audiences` フラグは存在
    # しないので、URI を明示的に set する形で「URI 1 件だけが accept される」
    # 状態を作る (GCP は allowed-audiences 未設定時も default で URI を accept
    # するので、URI 明示 set と機能的に等価)。
    local current_audiences expected_audience project_number
    current_audiences="$(gcloud iam workload-identity-pools providers describe "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
      --project="${BOOTSTRAP_PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
      --format="value(oidc.allowedAudiences)" 2>/dev/null || true)"
    project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null)"
    expected_audience="//iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/providers/${WORKLOAD_IDENTITY_PROVIDER_ID}"
    if [[ -n "${current_audiences}" && "${current_audiences}" != *"${expected_audience}"* ]]; then
      info "  Existing provider has legacy allowed-audiences (${current_audiences}). Updating to provider full resource URI..."
      gcloud iam workload-identity-pools providers update-oidc "${WORKLOAD_IDENTITY_PROVIDER_ID}" \
        --project="${BOOTSTRAP_PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
        --allowed-audiences="${expected_audience}" > /dev/null
      info "  Allowed-audiences updated."
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
attribute.terraform_run_phase=assertion.terraform_run_phase,\
attribute.terraform_workspace_kind=assertion.terraform_workspace_name.startsWith(\"${FACTORY_WORKSPACE_PREFIX}\") ? \"factory\" : \"service\"" \
    --attribute-condition="assertion.terraform_organization_name == \"${TFC_ORGANIZATION_NAME}\""

  info "Workload Identity Provider created."
  propagate_sleep low "WIF provider to be visible before SA binding"
}
