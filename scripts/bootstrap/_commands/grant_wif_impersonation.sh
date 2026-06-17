# shellcheck shell=bash
# factory workspace (principalSet) → terraform-project-factory SA に
# workloadIdentityUser を付与し、impersonation を許可する。
#
# 旧実装は `attribute.terraform_organization/${ORG}` で「org 内の全 workspace」を
# 許可していたが、Factory SA は org/folder レベルの projectCreator +
# projectIamAdmin を持つ強権 SA のため、org 内のどの workspace からも成り代わり
# 可能＝過大な攻撃面だった。派生属性 `terraform_workspace_kind=factory`
# (workspace 名が ${FACTORY_WORKSPACE_PREFIX} で始まるもの) に限定し、
# firebase 設定用 {service}-{env} や実験 workspace からの impersonation を遮断する。
# provider 側の attribute-condition (org 一致) が外側のゲートとして残るので、
# 「自 org かつ factory workspace」の二重条件になる。
grant_wif_impersonation() {
  info "Granting workloadIdentityUser to factory workspaces (terraform_workspace_kind=factory)..."

  local project_number
  project_number="$(gcloud projects describe "${BOOTSTRAP_PROJECT_ID}" \
    --format='value(projectNumber)')"

  local member="principalSet://iam.googleapis.com/projects/${project_number}/locations/global/workloadIdentityPools/${WORKLOAD_IDENTITY_POOL_ID}/attribute.terraform_workspace_kind/factory"

  gcloud iam service-accounts add-iam-policy-binding "$(sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="${member}" \
    --quiet

  info "WIF impersonation binding created."
}
