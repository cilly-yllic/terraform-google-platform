# shellcheck shell=bash
# Terraform Project Factory SA に必要な IAM role を付与する。
#
# 配置 (placement) に応じてスコープを決める。**folder が org に優先**する
# (ensure_folder が BOOTSTRAP_FOLDER_ID を解決済み。folder mode では ORGANIZATION_ID が
# 同時に設定されていても folder スコープで付与し、blast radius を folder 内に
# 封じ込める)。
#   Folder mode (BOOTSTRAP_FOLDER_ID あり)  : projectCreator + projectIamAdmin (folder スコープ)
#                                   (folder には billing IAM の親子関係が無いので、
#                                   billing は下の per-account grant に委ねる)
#   Org-direct mode (FOLDER 無し)  : projectCreator + projectIamAdmin + billing.user
#                                   (billing.user を org-level に上げると org 所有の
#                                   全 billing account に inherit され、billing account
#                                   追加時の手動 grant が不要になる利便性のため)
#   Billing Account (BOOTSTRAP_BILLING_ACCOUNT_ID, 常時)
#                                : billing.user (.env の bootstrap project
#                                  本体用 billing は per-account でも明示的
#                                  に付与。ORG_ID set 時は org-level grant と
#                                  重複するが冪等で実害なし)
#   Bootstrap Project            : (付与なし)
#
# Bootstrap project に Factory SA のロールを付与しない理由:
#   Factory SA が project-bootstrap module 実行時に行う操作は全て「作成した
#   ターゲット project 内」に閉じる (project 作成 / API 有効化 / per-env SA 作成 /
#   owner 付与 / per-env SA への WIF binding)。これらは org/folder の
#   projectCreator + projectIamAdmin と、作成 project への owner で充足する。
#   かつて必要だった bootstrap project の project number 読み取り
#   (data.google_project) は、action が渡す bootstrap_project_number 変数に
#   置き換えたため、infra への read role すら不要になった。
#   → Factory SA の infra footprint をゼロにする (最小権限)。
#
# 外部 (別 org) の billing account を後から追加する場合は `make grant-billing
# BILLING=<id>` を使う (scripts/grant-billing.sh が同 SA に per-account 付与)。
grant_iam() {
  info "Granting IAM roles to $(sa_email)..."

  local member
  member="serviceAccount:$(sa_email)"

  # --- Folder or Organization level (folder 優先) ---
  if [[ -n "${BOOTSTRAP_FOLDER_ID:-}" ]]; then
    # folder mode: 付与を folder スコープに限定し、Factory SA の到達範囲を
    # その folder 内に封じ込める。billing は folder に inherit しないので
    # 下の per-account grant に委ねる。
    local folder_roles=(
      roles/resourcemanager.projectCreator
      roles/resourcemanager.projectIamAdmin
    )
    for role in "${folder_roles[@]}"; do
      info "  Folder: ${role}"
      gcloud resource-manager folders add-iam-policy-binding "${BOOTSTRAP_FOLDER_ID}" \
        --member="${member}" \
        --role="${role}" \
        --quiet
    done
  else
    # org-direct mode: folder が無いので org スコープで付与 (floor)。
    # billing.user も org-level に含めると org 所有の全 billing account に
    # inherit され、billing account 追加時の手動 grant が不要になる。
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
  fi

  # --- Billing Account (.env の bootstrap project 本体用) ---
  # ORG_ID set 時は org-level grant と重複するが、冪等なので no-op。
  # BOOTSTRAP_FOLDER_ID only setup でも bootstrap project の billing 紐付けが回るよう
  # に常時 per-account 付与する。
  info "  Billing: roles/billing.user (on ${BOOTSTRAP_BILLING_ACCOUNT_ID})"
  gcloud billing accounts add-iam-policy-binding "${BOOTSTRAP_BILLING_ACCOUNT_ID}" \
    --member="${member}" \
    --role="roles/billing.user" \
    --quiet

  # --- infra-bootstrap Project: 付与なし (header コメント参照) ---

  info "IAM roles granted."
}
