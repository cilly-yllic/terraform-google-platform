# shellcheck shell=bash
# 既存の WIF Pool (TFC 用) に追加で GitHub Actions 用 OIDC Provider を載せる。
# - issuer は GitHub Actions 固定
# - allowed-audiences は指定しない (= provider full resource name が default audience)
# - attribute condition は **org (repository_owner) 単位**で縛る。
#
# なぜ org 単位か:
#   provider の condition は「誰が federation できるか」の入口ゲート。個々の repo
#   制限は「各 SA の workloadIdentityUser binding の principalSet
#   attribute.repository/{owner}/{repo}」で行う (provider=issuer+org のゲート /
#   binding=repo 単位の精密スコープ)。これにより、各サービス repo の GitHub Actions が
#   それぞれの firebase project の ci_service_account を impersonate して deploy できる。
#   旧実装は単一 repo (assertion.repository == "${GITHUB_REPOSITORY}") に絞っており、
#   bootstrap repo 以外のサービス repo が federation できず、ci_service_account.wif
#   (settings.yml) の repo binding が機能しなかった。
#
#   GITHUB_OWNER 未指定時は GITHUB_REPOSITORY の owner 部分 (owner/repo の owner) を使う。
#   deploy SA 側の binding (grant_github_wif_binding) は引き続き
#   attribute.repository/${GITHUB_REPOSITORY} で bootstrap repo 限定なので、
#   provider を広げても deploy SA への到達は infra repo のみに保たれる。
create_github_wif_provider() {
  local github_owner expected_condition
  github_owner="${GITHUB_OWNER:-${GITHUB_REPOSITORY%%/*}}"
  expected_condition="assertion.repository_owner == \"${github_owner}\""

  info "Creating GitHub WIF Provider $(github_provider_id) (org-scoped: ${github_owner})..."
  if github_provider_exists; then
    # 既存 provider が legacy (単一 repo condition) の場合、org 単位 condition に
    # 張り替える migration。
    local current_condition
    current_condition="$(gcloud iam workload-identity-pools providers describe "$(github_provider_id)" \
      --project="${BOOTSTRAP_PROJECT_ID}" \
      --location="global" \
      --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
      --format="value(attributeCondition)" 2>/dev/null || true)"
    if [[ "${current_condition}" != "${expected_condition}" ]]; then
      info "  Existing provider condition differs (${current_condition}). Updating to org-scoped: ${expected_condition}..."
      gcloud iam workload-identity-pools providers update-oidc "$(github_provider_id)" \
        --project="${BOOTSTRAP_PROJECT_ID}" \
        --location="global" \
        --workload-identity-pool="${WORKLOAD_IDENTITY_POOL_ID}" \
        --attribute-condition="${expected_condition}" > /dev/null
      info "  Attribute-condition updated."
    else
      info "GitHub WIF Provider $(github_provider_id) already exists with expected condition. Skipping."
    fi
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
    --attribute-condition="${expected_condition}"

  info "GitHub WIF Provider created (org-scoped: ${github_owner})."
  propagate_sleep low "WIF provider to be visible before SA binding"
}
