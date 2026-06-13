# shellcheck shell=bash
# 既存の WIF Pool (TFC 用) に追加で GitHub Actions 用 OIDC Provider を載せる。
# - issuer は GitHub Actions 固定
# - allowed-audiences は指定しない (= デフォルトは provider full resource name で
#   google-github-actions/auth がそのまま使う形式)
# - attribute condition で 1 つの repo に厳しく絞る
create_github_wif_provider() {
  info "Creating GitHub WIF Provider $(github_provider_id)..."
  if github_provider_exists; then
    info "GitHub WIF Provider $(github_provider_id) already exists. Skipping."
    return
  fi

  gcloud iam workload-identity-pools providers create-oidc "$(github_provider_id)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --location="global" \
    --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
    --display-name="${GITHUB_WIF_PROVIDER_DISPLAY_NAME:-GitHub Actions}" \
    --issuer-uri="${GITHUB_OIDC_ISSUER_URI}" \
    --attribute-mapping="\
google.subject=assertion.sub,\
attribute.repository=assertion.repository,\
attribute.repository_owner=assertion.repository_owner,\
attribute.ref=assertion.ref,\
attribute.actor=assertion.actor,\
attribute.workflow=assertion.workflow" \
    --attribute-condition="assertion.repository == \"${GITHUB_REPOSITORY}\""

  info "GitHub WIF Provider created."
  propagate_sleep low "WIF provider to be visible before SA binding"
}
