# shellcheck shell=bash
# Terraform Project Factory SA に必要な IAM role を付与する。
#   Organization (ORG_ID 設定時) : projectCreator + projectIamAdmin + billing.user
#                                  (billing.user を org-level に上げることで、
#                                  org が所有する全 billing account に
#                                  inherit され、サービスごとの billing
#                                  account 追加で手動 grant が不要になる)
#   Folder (FOLDER_ID のみ設定時) : projectCreator + projectIamAdmin
#                                   (folder には billing IAM の親子関係が
#                                   無いので、`.env` の BILLING_ACCOUNT_ID
#                                   に per-account grant する fallback 動作)
#   Billing Account (BILLING_ACCOUNT_ID, 常時)
#                                : billing.user (.env の bootstrap project
#                                  本体用 billing は per-account でも明示的
#                                  に付与。ORG_ID set 時は org-level grant と
#                                  重複するが冪等で実害なし)
#   Bootstrap Project            : serviceAccountAdmin + workloadIdentityPoolAdmin
#
# 外部 (別 org) の billing account を後から追加する場合は `make grant-billing
# BILLING=<id>` を使う (scripts/grant-billing.sh が同 SA に per-account 付与)。
grant_iam() {
  info "Granting IAM roles to $(sa_email)..."

  local member
  member="serviceAccount:$(sa_email)"

  # --- Organization or Folder level ---
  if [[ -n "${ORGANIZATION_ID:-}" ]]; then
    # billing.user を org-level に含める。これで org が所有する全 billing
    # account に inherit されるため、サービス側 settings.yml に新しい
    # billing account を書き足しても再 grant 不要になる。
    local org_roles=(
      roles/resourcemanager.projectCreator
      roles/resourcemanager.projectIamAdmin
      roles/billing.user
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

  # --- Billing Account (.env の bootstrap project 本体用) ---
  # ORG_ID set 時は org-level grant と重複するが、冪等なので no-op。
  # FOLDER_ID only setup でも bootstrap project の billing 紐付けが回るよう
  # に常時 per-account 付与する。
  info "  Billing: roles/billing.user (on ${BILLING_ACCOUNT_ID})"
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
