# shellcheck shell=bash
# Cloud Run deploy SA / runtime SA に必要な IAM role を付与する。
#
#   Deploy SA (project レベル):
#     run.developer                     : Cloud Run service の deploy / 更新
#     artifactregistry.writer           : container image を push
#     cloudbuild.builds.editor          : `gcloud builds submit` で Cloud Build job 発行
#     storage.admin                     : Cloud Build が source upload に GCS bucket を使う
#     iam.serviceAccountTokenCreator    : runtime SA の token を発行 (Cloud Run service 起動時の impersonation)
#   Deploy SA → Runtime SA:
#     iam.serviceAccountUser            : Cloud Run service の `--service-account=<runtime>` 指定用
#   Runtime SA (project レベル):
#     secretmanager.secretAccessor      : Cloud Run service runtime での secret 読み取り
grant_cloud_run_deploy_iam() {
  info "Granting IAM roles to Cloud Run deploy / runtime SAs..."

  local deploy_member runtime_member
  deploy_member="serviceAccount:$(deploy_sa_email)"
  runtime_member="serviceAccount:$(runtime_sa_email)"

  local deploy_project_roles=(
    roles/run.developer
    roles/artifactregistry.writer
    roles/cloudbuild.builds.editor
    roles/storage.admin
    roles/iam.serviceAccountTokenCreator
  )
  for role in "${deploy_project_roles[@]}"; do
    info "  Deploy SA / Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${deploy_member}" \
      --role="${role}" \
      --quiet
  done

  info "  Deploy SA / Runtime SA: roles/iam.serviceAccountUser"
  gcloud iam service-accounts add-iam-policy-binding "$(runtime_sa_email)" \
    --project="${BOOTSTRAP_PROJECT_ID}" \
    --member="${deploy_member}" \
    --role="roles/iam.serviceAccountUser" \
    --quiet

  local runtime_project_roles=(
    roles/secretmanager.secretAccessor
  )
  for role in "${runtime_project_roles[@]}"; do
    info "  Runtime SA / Project: ${role}"
    gcloud projects add-iam-policy-binding "${BOOTSTRAP_PROJECT_ID}" \
      --member="${runtime_member}" \
      --role="${role}" \
      --quiet
  done

  info "Cloud Run deploy IAM roles granted."
}
