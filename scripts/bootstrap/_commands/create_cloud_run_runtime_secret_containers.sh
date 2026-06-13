# shellcheck shell=bash
# Cloud Run runtime が読む Secret Manager container を **空で** 作成する。
# 値の投入 (= version 追加) は deploy workflow の sync step (GitHub Secret →
# `gcloud secrets versions add`) で行う想定なので、ここでは container だけ
# 用意する。既に存在する container は skip (冪等)。
#
# こうしておくと:
#   - deploy SA は `secretmanager.secretCreator` を持つ必要がない (container は
#     既存 = create 不要)
#   - deploy SA に最小限の `secretmanager.secretVersionAdder` だけ付与すれば
#     deploy 時の sync が動く
create_cloud_run_runtime_secret_containers() {
  info "Creating empty Secret Manager containers for cloud-run-router runtime..."
  local secret
  for secret in tfc-notification-secret github-app-private-key; do
    if runtime_secret_exists "${secret}"; then
      info "  Container '${secret}' already exists. Skipping."
    else
      info "  Creating empty container '${secret}'..."
      gcloud secrets create "${secret}" \
        --project="${BOOTSTRAP_PROJECT_ID}" \
        --replication-policy=automatic > /dev/null
      info "  Created '${secret}' (no versions yet — populated by deploy workflow)."
    fi
  done
  info "Runtime secret containers ready."
}
